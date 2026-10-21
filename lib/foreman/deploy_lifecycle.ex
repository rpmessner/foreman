defmodule Foreman.DeployLifecycle do
  @moduledoc "Deployment and rollback ordering; effects are interpreted by Foreman.Deploy."
  use Foreman.Fsm

  initial(:ready)
  state(:ready)
  state(:building)
  state(:installing)
  state(:stopping)
  state(:switching)
  state(:starting)
  state(:smoking)
  state(:cli)
  state(:rolling_back)
  state(:done)
  state(:failed)

  event(:begin)
  event(:succeeded)
  event(:failed)
  effects([:run])

  transition(:begin, from: :ready, to: :building, do: [run: :build])
  transition(:succeeded, from: :building, to: :installing, do: [run: :install])
  transition(:succeeded, from: :installing, to: :stopping, do: [run: :stop])
  transition(:succeeded, from: :stopping, to: :switching, do: [run: :switch])
  transition(:succeeded, from: :switching, to: :starting, do: [run: :start])
  transition(:succeeded, from: :starting, to: :smoking, do: [run: :smoke])
  transition(:succeeded, from: :smoking, to: :cli, do: [run: :cli])
  transition(:succeeded, from: :cli, to: :done)
  transition(:succeeded, from: :rolling_back, to: :failed)

  transition(:failed,
    from: [:stopping, :switching, :starting, :smoking],
    to: :rolling_back,
    do: [run: :rollback]
  )

  transition(:failed, from: [:building, :installing, :cli, :rolling_back], to: :failed)
  invalid([:begin, :succeeded, :failed], from: :any)
end
