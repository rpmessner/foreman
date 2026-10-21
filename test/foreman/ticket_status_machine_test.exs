defmodule Foreman.TicketStatusMachineTest do
  use ExUnit.Case, async: true
  alias Foreman.TicketStatusMachine, as: Machine

  test "tickets can be put on hold and resumed or closed from every state" do
    assert :on_hold in Machine.__fsm__(:states)

    for state <- Machine.__fsm__(:states) do
      assert Machine.step(state, :hold, nil) == {:on_hold, []}
    end

    for {event, state} <- [reopen: :open, start: :in_progress, close: :closed, defer: :deferred] do
      assert Machine.step(:on_hold, event, nil) == {state, []}
    end
  end
end
