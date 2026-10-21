defmodule Foreman.Deploy do
  @moduledoc "Guarded release deployment, with commands isolated at the OS boundary."

  @switches [
    dry_run: :boolean,
    allow_dirty: :boolean,
    allow_non_main: :boolean,
    releases_dir: :string,
    web_unit: :string,
    worker_unit: :string,
    cli_path: :string
  ]

  def run(args, opts \\ []) do
    with {:ok, config} <- configure(args, opts),
         :ok <- preflight(config) do
      plan = plan(config)
      if config.dry_run, do: {:ok, plan}, else: execute(config, plan)
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp configure(args, opts) do
    {flags, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      {:error, "Unknown arguments: #{inspect(rest ++ invalid)}"}
    else
      releases = Path.expand(flags[:releases_dir] || "~/.local/lib/foreman/releases")
      current = Path.join(Path.dirname(releases), "current")
      id = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%S.%fZ")

      {:ok,
       %{
         cwd: Keyword.get(opts, :cwd, File.cwd!()),
         command: Keyword.get(opts, :command, &os_command/3),
         releases: releases,
         current: current,
         target: Path.join(releases, id),
         id: id,
         cli: Path.expand(flags[:cli_path] || "~/.local/bin/foreman"),
         web: flags[:web_unit] || "foreman-web.service",
         worker: flags[:worker_unit] || "foreman-worker.service",
         dry_run: flags[:dry_run] || false,
         allow_dirty: flags[:allow_dirty] || false,
         allow_non_main: flags[:allow_non_main] || false
       }}
    end
  end

  defp preflight(c) do
    with :ok <- validate_units(c),
         {dirty, 0} <- command(c, "git", ["status", "--porcelain"]),
         {branch, 0} <- command(c, "git", ["branch", "--show-current"]) do
      cond do
        dirty != "" and not c.allow_dirty ->
          {:error, "Dirty tree; commit changes or pass --allow-dirty"}

        String.trim(branch) != "main" and not c.allow_non_main ->
          {:error, "Not on main; pass --allow-non-main to override"}

        not File.exists?(Path.join(c.current, "bin/foreman")) ->
          {:error, "current must point to an existing release (initial install: see README)"}

        not match?({:ok, _}, File.read_link(c.current)) ->
          {:error, "current must be a symlink"}

        true ->
          :ok
      end
    else
      {:error, _} = error -> error
      _ -> {:error, "Git preflight failed"}
    end
  end

  defp validate_units(c) do
    units = [c.web, c.worker]

    if String.trim_trailing(c.web, ".service") != String.trim_trailing(c.worker, ".service") and
         Enum.all?(units, fn unit ->
           Regex.match?(~r/\A[a-zA-Z0-9_][a-zA-Z0-9_-]*(?:\.service)?\z/, unit) and
             not String.contains?(String.downcase(unit), "tmux")
         end) do
      :ok
    else
      {:error, "Use distinct, literal web/worker service names; tmux units are forbidden"}
    end
  end

  defp plan(c) do
    """
    Release #{c.id}
    MIX_ENV=prod mix compile
    MIX_ENV=prod mix assets.deploy
    MIX_ENV=prod mix release --overwrite
    Copy _build/prod/rel/foreman/. to #{c.target}
    systemctl --user stop #{c.worker} #{c.web}
    Atomically switch #{c.current} to #{c.target}
    systemctl --user start #{c.web} #{c.worker}
    python3 tools/release-smoke.py --release #{c.target}
    Rollback on stop/switch/start/smoke failure: stop worker/web, restore previous current, start web/worker
    MIX_ENV=dev mix escript.build
    Install foreman to #{c.cli}
    Keep all old releases; never control the tmux service
    """
  end

  defp os_command("git", args, opts), do: System.cmd("git", args, opts)

  defp os_command(executable, args, opts) do
    System.cmd(executable, args, Keyword.put(opts, :into, IO.stream(:stdio, :line)))
  end

  defp command(c, executable, args, env \\ []) do
    c.command.(executable, args, cd: c.cwd, env: env, stderr_to_stdout: true)
  end

  defp execute(c, plan) do
    File.mkdir_p!(c.releases)
    lock = Path.join(c.releases, ".deploy-lock")

    case File.mkdir(lock) do
      :ok ->
        try do
          previous = File.read_link!(c.current)

          drive(
            :ready,
            :begin,
            Map.merge(c, %{previous: previous, error: "", smoke_result: "not run", plan: plan})
          )
        after
          File.rmdir!(lock)
        end

      {:error, :eexist} ->
        {:error, "Deployment lock exists: #{lock}; another deploy may be running"}

      {:error, reason} ->
        {:error, "Cannot acquire deployment lock: #{inspect(reason)}"}
    end
  end

  defp drive(state, event, c) do
    {next, effects} = Foreman.DeployLifecycle.step(state, event, c)

    case {next, effects} do
      {:done, []} ->
        {:ok, c.plan <> "Smoke passed; release #{c.id}; CLI installed\n"}

      {:failed, []} ->
        {:error, "Release #{c.id}; Smoke #{c.smoke_result}: #{c.error}"}

      {_, [run: operation]} ->
        case safely(fn -> perform(operation, c) end) do
          :ok ->
            c =
              if operation == :rollback,
                do: %{c | error: c.error <> "; Rollback succeeded"},
                else: c

            c = if operation == :smoke, do: %{c | smoke_result: "passed"}, else: c
            drive(next, :succeeded, c)

          {:error, message} ->
            c = if operation == :smoke, do: %{c | smoke_result: "failed"}, else: c

            drive(next, :failed, %{
              c
              | error: Enum.join(Enum.reject([c.error, message], &(&1 == "")), "; ")
            })
        end
    end
  end

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp perform(:build, c) do
    Enum.reduce_while([["compile"], ["assets.deploy"], ["release", "--overwrite"]], :ok, fn args,
                                                                                            _ ->
      case checked(c, "mix", args, [{"MIX_ENV", "prod"}]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp perform(:install, c) do
    File.mkdir!(c.target)
    source = Path.join(c.cwd, "_build/prod/rel/foreman")
    File.cp_r!(source <> "/.", c.target)
    true = File.exists?(Path.join(c.target, "bin/foreman"))
    :ok
  end

  defp perform(:stop, c), do: checked(c, "systemctl", ["--user", "stop", c.worker, c.web])
  defp perform(:switch, c), do: switch(c, c.target)
  defp perform(:start, c), do: checked(c, "systemctl", ["--user", "start", c.web, c.worker])

  defp perform(:smoke, c) do
    case checked(c, "python3", ["tools/release-smoke.py", "--release", c.target]) do
      :ok -> :ok
      {:error, message} -> {:error, "Smoke failed: #{message}"}
    end
  end

  defp perform(:cli, c) do
    with :ok <- checked(c, "mix", ["escript.build"], [{"MIX_ENV", "dev"}]) do
      File.mkdir_p!(Path.dirname(c.cli))
      temporary = c.cli <> ".deploy-" <> c.id

      try do
        File.cp!(Path.join(c.cwd, "foreman"), temporary)
        File.chmod!(temporary, 0o755)
        File.rename!(temporary, c.cli)
        :ok
      after
        File.rm(temporary)
      end
    end
  end

  defp perform(:rollback, c) do
    results = [
      safely(fn -> perform(:stop, c) end),
      safely(fn -> switch(c, c.previous) end),
      safely(fn -> perform(:start, c) end)
    ]

    case for({:error, reason} <- results, do: reason) do
      [] -> :ok
      errors -> {:error, "Rollback FAILED; manual recovery required: " <> Enum.join(errors, "; ")}
    end
  end

  defp switch(c, target) do
    temporary = c.current <> ".deploy-" <> c.id

    try do
      with :ok <- checked(c, "ln", ["-s", target, temporary]),
           :ok <- checked(c, "mv", ["-Tf", temporary, c.current]) do
        :ok
      end
    after
      File.rm(temporary)
    end
  end

  defp checked(c, executable, args, env \\ []) do
    case command(c, executable, args, env) do
      {_output, 0} -> :ok
      {_output, status} -> {:error, "#{executable} #{Enum.join(args, " ")} exited #{status}"}
    end
  end
end
