defmodule Mix.Tasks.Foreman.Deploy do
  use Mix.Task

  @requirements ["compile"]
  @shortdoc "Build, migrate, switch, smoke and install a Foreman release and CLI"
  @moduledoc """
  Upgrades an existing user-service installation, migrating before stopping services.
  Does not install units.

      mix foreman.deploy [--dry-run] [--allow-dirty] [--allow-non-main]

  Options:
    * `--releases-dir PATH` — defaults to `~/.local/lib/foreman/releases`;
      `current` is its sibling symlink.
    * `--web-unit NAME` — defaults to `foreman-web.service`.
    * `--worker-unit NAME` — defaults to `foreman-worker.service`.
    * `--cli-path PATH` — defaults to `~/.local/bin/foreman`.
    * `--env-file PATH` — overrides installed units' EnvironmentFiles discovery.
      Files are parsed as data. Only database settings reach the migration child.

  Migration failure leaves current and services untouched; migration output is
  suppressed to protect credentials. Schema changes are not rolled back.
  Old releases are retained. Failures during service switching or smoke restore
  the previous symlink and start web/worker. CLI failures retain the healthy new
  release. Unit names must be literal service names, never tmux units or globs.
  After Mix compiles the checkout tooling, dry runs perform only read-only
  preflight checks and print the plan; no deployment effects are executed.
  Pending names are queried read-only with the built new release only when
  --env-file explicitly permits loading credentials; otherwise listing is unavailable.
  """

  @impl true
  def run(args) do
    case Foreman.Deploy.run(args) do
      {:ok, output} -> Mix.shell().info(output)
      {:error, reason} -> Mix.raise(reason)
    end
  end
end
