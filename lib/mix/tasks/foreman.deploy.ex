defmodule Mix.Tasks.Foreman.Deploy do
  use Mix.Task

  @requirements ["compile"]
  @shortdoc "Build, switch, smoke and install a Foreman release and CLI"
  @moduledoc """
  Upgrades an existing user-service installation; does not install units or migrate the database.

      mix foreman.deploy [--dry-run] [--allow-dirty] [--allow-non-main]

  Options:
    * `--releases-dir PATH` — defaults to `~/.local/lib/foreman/releases`;
      `current` is its sibling symlink.
    * `--web-unit NAME` — defaults to `foreman-web.service`.
    * `--worker-unit NAME` — defaults to `foreman-worker.service`.
    * `--cli-path PATH` — defaults to `~/.local/bin/foreman`.

  Old releases are retained. Failures during service switching or smoke restore
  the previous symlink and start web/worker. CLI failures retain the healthy new
  release. Unit names must be literal service names, never tmux units or globs.
  After Mix compiles the checkout tooling, dry runs perform only read-only
  preflight checks and print the plan; no deployment effects are executed.
  """

  @impl true
  def run(args) do
    case Foreman.Deploy.run(args) do
      {:ok, output} -> Mix.shell().info(output)
      {:error, reason} -> Mix.raise(reason)
    end
  end
end
