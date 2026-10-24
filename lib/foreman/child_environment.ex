defmodule Foreman.ChildEnvironment do
  @moduledoc "Pure environment and shell-command boundary for user sessions."

  @runtime_names ~w(ERL_ROOTDIR ROOTDIR BINDIR EMU PROGNAME)
  @service_names ~w(FOREMAN_DATABASE_URL SECRET_KEY_BASE)

  def clean(environment) do
    paths = String.split(Map.get(environment, "PATH", ""), ":")

    roots =
      [environment["RELEASE_ROOT"], environment["ROOTDIR"]] ++
        for path <- paths,
            erts_bin?(path),
            do: path |> String.trim_trailing("/") |> Path.dirname() |> Path.dirname()

    release_bins = for root <- roots, is_binary(root) and root != "", do: Path.join(root, "bin")

    environment
    |> Map.reject(fn {name, _} ->
      String.starts_with?(name, ["RELEASE_", "PHX_", "ERTS_"]) or
        name in @runtime_names or name in @service_names
    end)
    |> then(fn clean ->
      if Map.has_key?(environment, "PATH") do
        Map.put(
          clean,
          "PATH",
          Enum.reject(paths, &(erts_bin?(&1) or String.trim_trailing(&1, "/") in release_bins))
          |> Enum.join(":")
        )
      else
        clean
      end
    end)
  end

  @doc "An exec command; assignments and argv are shell-quoted, never evaluated as code."
  def command(environment, argv) do
    assignments =
      environment |> clean() |> Enum.sort() |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)

    "exec /usr/bin/env -i " <> Enum.map_join(assignments ++ argv, " ", &quote_arg/1)
  end

  defp quote_arg(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp erts_bin?(path), do: Regex.match?(~r{/erts-[^/]+/bin/?\z}, path)
end
