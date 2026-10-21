defmodule Foreman.PriorityOverride do
  @moduledoc "Priority ownership: a board override yields when the ticket file agrees."
  use Foreman.Fsm, observed_never_invalid: true

  initial(:file)
  state(:file)
  state(:board)
  event(:set)
  event(:synced, source: :observed)
  effects([:store, :clear])
  guard(:matches_file?)

  transition(:set, from: :file, to: :stay, guard: :matches_file?)
  transition(:set, from: :file, to: :board, do: [store: :override])
  transition(:set, from: :board, to: :file, guard: :matches_file?, do: [clear: :override])
  transition(:set, from: :board, to: :stay, do: [store: :override])
  transition(:synced, from: :board, to: :file, guard: :matches_file?, do: [clear: :override])
  transition(:synced, from: :board, to: :stay)
  ignore(:synced, from: :file)

  def matches_file?(_, %{priority: priority, file: file}), do: priority == file
  def matches_file?(_, _), do: false
end
