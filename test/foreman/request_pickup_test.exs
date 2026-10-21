defmodule Foreman.RequestPickupTest do
  use Foreman.DataCase, async: false
  alias Foreman.{Overlay, Requests, Repo}
  import Ecto.Query

  setup do
    Overlay.backfill("pickup", [%{bead_id: "p-1", status: "open", issue_type: "task"}])

    {:ok, request} =
      Requests.ask({"pickup", "p-1"}, "decision", %{
        "session" => "build",
        "facts" => %{"question" => "Which?"}
      })

    %{request: request}
  end

  test "a timed out wait leaves an answer visible until a later wait picks it up", %{request: r} do
    refute Requests.live_wait?(r)
    assert {:ok, _} = Requests.wait(r.id, 0)

    assert {:ok, orphan} =
             Requests.resolve(r.id, :answer, %{"answer" => "A", "note" => "Keep it"})

    assert orphan.state == "not_picked_up"
    assert {:ok, picked} = Requests.wait(r.id, 0)
    assert picked.state == "answered"
    assert picked.outcome == %{"answer" => "A"}
    assert picked.note == "Keep it"
    assert {:ok, _} = Requests.wait(r.id, 0)
    uuid = Ecto.UUID.dump!(r.id)

    assert Repo.aggregate(
             from(e in "request_events",
               where: e.request_id == ^uuid and e.to_state == "not_picked_up"
             ),
             :count
           ) == 1
  end

  test "agent wait renews and then collects rather than reading a stranded answer", %{request: r} do
    assert {200, %{"state" => "pending"}} =
             Foreman.AgentCommands.execute(%{
               "action" => "wait",
               "id" => r.id,
               "lease_ms" => 2000
             })

    assert Requests.live_wait?(r)
    Requests.wait(r.id, 0)
    Requests.resolve(r.id, :answer, %{"answer" => "A"})

    assert {200, %{"state" => "answered", "outcome" => %{"answer" => "A"}}} =
             Foreman.AgentCommands.execute(%{"action" => "wait", "id" => r.id})

    assert Requests.get(r.id).state == "answered"
  end

  test "the runtime detects a waiter that exits after the answer without collecting it", %{
    request: r
  } do
    Requests.wait(r.id, 2000)
    Requests.resolve(r.id, :answer, %{"answer" => "A"})
    uuid = Ecto.UUID.dump!(r.id)

    Repo.update_all(
      from(e in "request_events", where: e.request_id == ^uuid and e.event == "wait"),
      set: [payload: %{"until" => "2000-01-01T00:00:00Z"}]
    )

    Requests.reconcile_pickups()
    assert Requests.get(r.id).state == "not_picked_up"
    Requests.reconcile_pickups()

    assert Repo.aggregate(
             from(e in "request_events", where: e.request_id == ^uuid and e.event == "wait_lost"),
             :count
           ) == 1
  end

  test "a reported session cannot hold an answer with its old lease", %{request: r} do
    assert {:ok, _} = Overlay.apply_event({"pickup", "p-1"}, {:dispatch, %{window: "build"}})
    Requests.wait(r.id, 2000)
    assert Requests.live_wait?(r)

    assert {:ok, _} =
             Overlay.apply_event(
               {"pickup", "p-1"},
               {:report, %{window: "build", path: "report.md"}}
             )

    refute Requests.live_wait?(r)
    assert {:ok, %{state: "not_picked_up"}} = Requests.resolve(r.id, :answer, %{"answer" => "A"})
    assert {:ok, %{state: "answered"}} = Requests.wait(r.id, 0)
  end

  test "an ended session cannot hold an answer with its old lease", %{request: r} do
    now = DateTime.utc_now()

    Repo.insert_all("sessions", [
      %{
        repo_key: "pickup",
        bead_id: "p-1",
        window: "build",
        details: %{},
        started_at: now,
        last_seen_at: now,
        ended_at: now
      }
    ])

    Requests.wait(r.id, 2000)
    refute Requests.live_wait?(r)
  end

  test "reconciliation does not resurrect pre-tracking answered requests", %{request: r} do
    r
    |> Ecto.Changeset.change(state: "answered", outcome: %{"answer" => "Legacy"})
    |> Repo.update!()

    Requests.reconcile_pickups()
    assert Requests.get(r.id).state == "answered"
  end

  test "a gone planning session invalidates its lease", %{request: r} do
    Repo.insert!(%Foreman.PlanningSession{
      project: "pickup",
      ticket: "p-1",
      workdir: "/tmp",
      window: "build",
      state: :parked,
      launched_at: DateTime.utc_now()
    })

    Requests.wait(r.id, 2000)
    refute Requests.live_wait?(r)
  end

  test "a session UUID resolves liveness as well as its tmux window", %{request: r} do
    session =
      Repo.insert!(%Foreman.PlanningSession{
        project: "pickup",
        ticket: "p-1",
        workdir: "/tmp",
        window: "@7",
        state: :ended,
        launched_at: DateTime.utc_now()
      })

    r = r |> Ecto.Changeset.change(session: session.session_id) |> Repo.update!()
    Requests.wait(r.id, 2000)
    refute Requests.live_wait?(r)
  end

  test "a refused report does not end a live wait", %{request: r} do
    Requests.wait(r.id, 2000)

    assert {:error, _} =
             Overlay.apply_event(
               {"pickup", "p-1"},
               {:report, %{window: "build", path: "report.md"}}
             )

    assert Requests.live_wait?(r)
  end

  test "one waiter timing out does not cancel another live wait", %{request: r} do
    Requests.wait(r.id, 2000, "long")
    Requests.wait(r.id, 0, "short")
    assert Requests.live_wait?(r)
    Requests.wait(r.id, 0, "long")
    refute Requests.live_wait?(r)
  end

  test "a live wait expires at its deadline", %{request: r} do
    assert {:ok, _} = Requests.wait(r.id, 2000)
    assert Requests.live_wait?(r)
    refute Requests.live_wait?(r, DateTime.add(DateTime.utc_now(), 3, :second))
    assert {:ok, answered} = Requests.resolve(r.id, :answer, %{"answer" => "A"})
    assert answered.state == "answered"
    assert {:ok, _} = Requests.wait(r.id, 0)
    assert {:ok, same} = Requests.resolve(r.id, :wait_lost, %{})
    assert same.state == "answered"
  end
end
