defmodule Foreman.RequestMachineTest do
  use ExUnit.Case, async: true
  alias Foreman.Request, as: Machine

  test "an answer without a live waiter is retained until pickup" do
    context = %{kind: "decision", live_wait: false}

    assert Machine.step(:pending, :answer, context) ==
             {:not_picked_up, [record: :answer, notify: :coordinator]}

    assert Machine.step(:not_picked_up, :pickup, context) ==
             {:answered, [record: :pickup]}
  end

  test "wait rows and a lost waiter retain only uncollected decisions" do
    assert Machine.step(:pending, :wait, %{}) == {:pending, [record: :wait]}
    assert Machine.step(:answered, :pickup, %{}) == {:answered, [record: :pickup]}
    assert Machine.step(:answered, :pickup, %{picked_up: true}) == {:answered, []}

    assert Machine.step(:pending, :answer, %{kind: "decision", live_wait: true}) ==
             {:answered, [record: :answer, notify: :asker]}

    context = %{kind: "decision", live_wait: false, picked_up: false}

    assert Machine.step(:answered, :wait_lost, context) ==
             {:not_picked_up, [notify: :coordinator]}

    for context <- [
          %{context | live_wait: true},
          %{context | picked_up: true},
          %{context | kind: "push"}
        ] do
      assert Machine.step(:answered, :wait_lost, context) == {:answered, []}
    end
  end

  test "Continue is a pending usage-limit-only effect, never an approval job" do
    context = %{kind: "session_waiting", reason: "usage_limit"}
    assert Machine.step(:pending, :continue, context) == {:pending, [send: :continue]}

    for state <- Machine.__fsm__(:states), state != :pending do
      assert {:error, _} = Machine.step(state, :continue, context)
    end

    for context <- [
          %{kind: "session_waiting", reason: "input"},
          %{kind: "session_waiting", reason: "permission"},
          %{kind: "push", reason: "usage_limit"},
          %{kind: "decision", reason: "usage_limit"}
        ] do
      assert {:error, _} = Machine.step(:pending, :continue, context)
    end
  end

  test "an inline reply answers a single single-select question wait only" do
    question = %{"question" => "Which?", "options" => ["A", "B"], "multi" => false}
    context = %{kind: "session_waiting", reason: "input", questions: [question]}
    assert Machine.step(:pending, :reply, context) == {:answered, [send: :answer]}

    for state <- Machine.__fsm__(:states), state != :pending do
      assert {:error, _} = Machine.step(state, :reply, context)
    end

    for context <- [
          %{context | questions: nil},
          %{context | questions: [%{question | "multi" => true}]},
          %{context | questions: [Map.put(question, "preview", true)]},
          %{context | questions: [question, question]},
          %{context | questions: [%{question | "options" => []}]},
          %{context | reason: "permission"},
          %{context | kind: "decision"}
        ] do
      assert {:error, _} = Machine.step(:pending, :reply, context)
    end
  end

  test "a reply to a chat question types into the session prompt" do
    context = %{kind: "session_waiting", reason: "question", questions: nil}
    assert Machine.step(:pending, :reply, context) == {:answered, [send: :prompt]}

    for state <- Machine.__fsm__(:states), state != :pending do
      assert {:error, _} = Machine.step(state, :reply, context)
    end

    for context <- [%{context | reason: "input"}, %{context | kind: "decision"}] do
      assert {:error, _} = Machine.step(:pending, :reply, context)
    end
  end

  test "every request transition and its effects" do
    for {from, event, kind, to, effects} <- [
          {:new, :ask, "decision", :pending, [record: :request, notify: :pending]},
          {:pending, :approve, "push", :approved, [enqueue: :job]},
          {:pending, :answer, "decision", :answered, [record: :answer, notify: :asker]},
          {:pending, :decline, "decision", :declined, [record: :note, notify: :asker]},
          {:pending, :withdraw, "decision", :withdrawn, []},
          {:pending, :facts_changed, "decision", :superseded, [notify: :asker]},
          {:approved, :start, "push", :executing, [audit: :intent]},
          {:executing, :succeeded, "push", :done, [audit: :result, notify: :asker]},
          {:executing, :failed, "push", :failed, [audit: :reason, notify: :asker]},
          {:executing, :orphaned, "push", :failed, [audit: :unknown, notify: :asker]}
        ] do
      assert Machine.step(from, event, %{kind: kind}) == {to, effects}
    end
  end

  test "wrong kind claims are invalid" do
    assert {:error, _} = Machine.step(:pending, :approve, %{kind: "decision"})
    assert {:error, _} = Machine.step(:pending, :answer, %{kind: "push"})
  end

  test "all other declared pairs reject claims and ignore observations" do
    valid =
      MapSet.new([
        {:new, :ask},
        {:pending, :wait},
        {:answered, :pickup},
        {:not_picked_up, :pickup},
        {:pending, :approve},
        {:pending, :answer},
        {:pending, :decline},
        {:pending, :withdraw},
        {:pending, :facts_changed},
        {:approved, :start},
        {:executing, :succeeded},
        {:executing, :failed},
        {:executing, :orphaned}
      ])

    for state <- Machine.__fsm__(:states),
        {event, source} <- Machine.__fsm__(:sources),
        not MapSet.member?(valid, {state, event}) do
      result = Machine.step(state, event, %{kind: "decision"})

      if source == :observed,
        do: assert(result == {state, []}),
        else: assert(match?({:error, _}, result))
    end
  end
end
