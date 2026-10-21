defmodule Foreman.Request do
  @moduledoc "Request lifecycle; kind guards separate decisions from executable actions."
  use Foreman.Fsm, observed_never_invalid: true
  initial(:new)
  state(:new)
  state(:pending)
  state(:approved)
  state(:answered)
  state(:not_picked_up)
  state(:declined)
  state(:withdrawn)
  state(:superseded)
  state(:executing)
  state(:done)
  state(:failed)
  event(:ask)
  event(:approve)
  event(:answer)
  event(:wait)
  event(:pickup)
  event(:wait_lost, source: :observed)
  event(:decline)
  event(:withdraw)
  event(:continue)
  event(:reply)
  event(:start)
  event(:facts_changed, source: :observed)
  event(:succeeded, source: :observed)
  event(:failed, source: :observed)
  event(:orphaned, source: :observed)
  effects([:record, :notify, :enqueue, :audit, :send])
  guard(:decision?)
  guard(:unheld_decision?)
  guard(:uncollected?)
  guard(:unpicked?)
  guard(:action?)
  guard(:usage_limit?)
  guard(:inline_question?)
  guard(:chat_question?)
  transition(:ask, from: :new, to: :pending, do: [record: :request, notify: :pending])
  transition(:approve, from: :pending, to: :approved, guard: :action?, do: [enqueue: :job])

  transition(:wait, from: :pending, to: :pending, do: [record: :wait])
  transition(:pickup, from: :not_picked_up, to: :answered, do: [record: :pickup])
  transition(:pickup, from: :answered, to: :answered, guard: :unpicked?, do: [record: :pickup])
  ignore(:pickup, from: :answered)

  transition(:wait_lost,
    from: :answered,
    to: :not_picked_up,
    guard: :uncollected?,
    do: [notify: :coordinator]
  )

  transition(:answer,
    from: :pending,
    to: :not_picked_up,
    guard: :unheld_decision?,
    do: [record: :answer, notify: :coordinator]
  )

  transition(:answer,
    from: :pending,
    to: :answered,
    guard: :decision?,
    do: [record: :answer, notify: :asker]
  )

  transition(:decline, from: :pending, to: :declined, do: [record: :note, notify: :asker])
  transition(:withdraw, from: :pending, to: :withdrawn)
  transition(:continue, from: :pending, to: :pending, guard: :usage_limit?, do: [send: :continue])
  transition(:reply, from: :pending, to: :answered, guard: :inline_question?, do: [send: :answer])
  transition(:reply, from: :pending, to: :answered, guard: :chat_question?, do: [send: :prompt])
  transition(:facts_changed, from: :pending, to: :superseded, do: [notify: :asker])
  transition(:start, from: :approved, to: :executing, do: [audit: :intent])
  transition(:succeeded, from: :executing, to: :done, do: [audit: :result, notify: :asker])
  transition(:failed, from: :executing, to: :failed, do: [audit: :reason, notify: :asker])
  transition(:orphaned, from: :executing, to: :failed, do: [audit: :unknown, notify: :asker])
  ignore([:facts_changed, :succeeded, :failed, :orphaned, :wait_lost], from: :any)

  invalid(
    [:ask, :approve, :answer, :decline, :withdraw, :start, :continue, :reply, :wait, :pickup],
    from: :any
  )

  def unpicked?(context, _), do: not Map.get(context, :picked_up, false)

  def unheld_decision?(%{kind: "decision", live_wait: false}, _), do: true
  def unheld_decision?(_, _), do: false

  def uncollected?(%{kind: "decision", live_wait: false, picked_up: false}, _), do: true
  def uncollected?(_, _), do: false

  def usage_limit?(%{kind: "session_waiting", reason: "usage_limit"}, _), do: true
  def usage_limit?(_, _), do: false

  @doc "A session's question prompt foreman can answer from the card: one single-select question."
  def inline_question?(
        %{
          kind: "session_waiting",
          reason: "input",
          questions: [%{"multi" => false, "options" => [_ | _]} = question]
        },
        _
      ),
      do: Map.get(question, "preview", false) == false

  def inline_question?(_, _), do: false

  @doc "A session that ended its turn asking in chat; the reply goes into its prompt."
  def chat_question?(%{kind: "session_waiting", reason: "question"}, _), do: true
  def chat_question?(_, _), do: false

  def decision?(%{kind: "decision"}, _), do: true
  def decision?(_, _), do: false
  def action?(%{kind: kind}, _), do: kind in ["push", "open_pr", "merge"]
  def action?(_, _), do: false
end
