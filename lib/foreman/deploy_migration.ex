defmodule Foreman.DeployMigration do
  @moduledoc "Isolated release migration commands and environment-file data loading."
  @database_keys ~w(DATABASE_URL ECTO_IPV6 POOL_SIZE)

  def environment(%{env_file: path}) when is_binary(path) do
    load_files([{Path.expand(path), false}])
  rescue
    _ -> {:error, :environment_unavailable}
  end

  def environment(config) do
    with {:ok, worker} <- unit_environment(config, config.worker),
         {:ok, web} <- unit_environment(config, config.web),
         true <- worker == web do
      {:ok, worker}
    else
      _ -> {:error, :environment_unavailable}
    end
  rescue
    _ -> {:error, :environment_unavailable}
  end

  defp unit_environment(c, unit) do
    args = ["--user", "show", "--property=EnvironmentFiles", "--value", unit]

    with {output, 0} <-
           c.command.("systemctl", args, cd: c.cwd, env: [], into: "", stderr_to_stdout: true) do
      pattern = ~r/(\S+) \(ignore_errors=(yes|no)\)/
      matches = Regex.scan(pattern, String.trim(output))
      remainder = Regex.replace(pattern, output, "") |> String.trim()

      if matches != [] and remainder == "" do
        load_files(Enum.map(matches, fn [_, path, optional] -> {path, optional == "yes"} end))
      else
        {:error, :environment_unavailable}
      end
    else
      _ -> {:error, :environment_unavailable}
    end
  end

  defp load_files(files) do
    result =
      Enum.reduce_while(files, {:ok, %{}}, fn {path, optional}, {:ok, env} ->
        case File.read(path) do
          {:ok, contents} ->
            case parse(contents) do
              {:ok, values} -> {:cont, {:ok, Map.merge(env, values)}}
              error -> {:halt, error}
            end

          {:error, :enoent} when optional ->
            {:cont, {:ok, env}}

          _ ->
            {:halt, {:error, :environment_unavailable}}
        end
      end)

    case result do
      {:ok, env} when is_map_key(env, "DATABASE_URL") ->
        if env["DATABASE_URL"] == "" do
          {:error, :environment_unavailable}
        else
          {:ok, env |> Map.take(@database_keys) |> Enum.sort()}
        end

      _ ->
        {:error, :environment_unavailable}
    end
  end

  defp parse(contents) do
    contents
    |> String.split("\n")
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, env} ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, ["#", ";"]) ->
          {:cont, {:ok, env}}

        true ->
          case Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)\z/, line) do
            [_, key, raw] ->
              case value(String.trim(raw)) do
                {:ok, value} -> {:cont, {:ok, Map.put(env, key, value)}}
                :error -> {:halt, {:error, :unsupported_environment_syntax}}
              end

            _ ->
              {:halt, {:error, :unsupported_environment_syntax}}
          end
      end
    end)
  end

  defp value("'" <> _ = raw) do
    case Regex.run(~r/\A'([^']*)'\z/u, raw) do
      [_, value] -> {:ok, value}
      _ -> :error
    end
  end

  defp value("\"" <> _ = raw) do
    case Regex.run(~r/\A"((?:[^"\\]|\\.)*)"\z/u, raw) do
      [_, value] -> {:ok, String.replace(value, ~r/\\(["\\`$])/, "\\1")}
      _ -> :error
    end
  end

  defp value(raw) do
    if String.contains?(raw, ["\\", "\"", "'"]), do: :error, else: {:ok, raw}
  end

  def pending(%{env_file: nil}) do
    "Pending migrations unavailable: pass --env-file PATH to permit a database query with the built new release\n"
  end

  def pending(c) do
    release = Path.join(c.cwd, "_build/prod/rel/foreman")

    with true <- File.regular?(Path.join(release, "bin/foreman")),
         {:ok, env} <- environment(c),
         {executable, args, opts} <- command(release, env, :pending),
         {output, 0} <- c.command.(executable, args, opts ++ [cd: c.cwd, stderr_to_stdout: true]),
         true <- "FOREMAN_PENDING_DONE" in String.split(output, "\n") do
      names = Regex.scan(~r/^FOREMAN_PENDING ([0-9]+ [a-z0-9_]+)$/m, output)

      if names == [],
        do: "Pending migrations: none\n",
        else: "Pending migrations:\n" <> Enum.map_join(names, "\n", &List.last/1) <> "\n"
    else
      _ ->
        "Pending migrations unavailable: build the new release and supply a readable --env-file PATH\n"
    end
  rescue
    _ -> "Pending migrations unavailable: release query failed (output suppressed)\n"
  end

  def command(release, env, mode) do
    database =
      Map.merge(Map.new(@database_keys, &{&1, nil}), Map.take(Map.new(env), @database_keys))
      |> Map.to_list()

    {Path.join(release, "bin/foreman"), ["eval", expression(mode)],
     [
       into: "",
       env:
         database ++
           [
             {"FOREMAN_ROLE", "worker"},
             {"PHX_SERVER", nil},
             {"SECRET_KEY_BASE", nil},
             {"ERL_CRASH_DUMP", "/dev/null"},
             {"RELEASE_DISTRIBUTION", "none"}
           ]
     ]}
  end

  defp expression(:pending) do
    """
    Application.load(:foreman)
    {:ok, _, _} = Ecto.Migrator.with_repo(Foreman.Repo, fn repo ->
      for {:down, version, name} <- Ecto.Migrator.migrations(repo,
        [Ecto.Migrator.migrations_path(repo)], skip_table_creation: true, migration_lock: false) do
        IO.puts("FOREMAN_PENDING \#{version} \#{name}")
      end
    end)
    IO.puts("FOREMAN_PENDING_DONE")
    """
  end

  defp expression(:migrate) do
    """
    Application.load(:foreman)
    {:ok, _, _} = Ecto.Migrator.with_repo(Foreman.Repo, fn repo ->
      Ecto.Migrator.run(repo, :up, all: true)
    end)
    """
  end
end
