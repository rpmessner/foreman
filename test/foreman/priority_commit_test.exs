defmodule Foreman.PriorityCommitTest do
  use ExUnit.Case, async: false
  alias Foreman.{Priority, Repo, Beads.Projection}

  setup do
    repo = "priority-race-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      unboxed(fn ->
        Repo.query!(
          "DELETE FROM overlay_effects WHERE event_id IN (SELECT id FROM stage_events WHERE repo_key=$1)",
          [repo]
        )

        for table <- ~w(priority_overrides beads sessions stage_events tickets),
            do: Repo.query!("DELETE FROM #{table} WHERE repo_key=$1", [repo])

        Repo.query!("DELETE FROM bead_repos WHERE key=$1", [repo])
      end)
    end)

    %{repo: repo, key: {repo, "a"}}
  end

  test "a syncing file cannot clear a newer board edit on independent connections", %{
    repo: repo,
    key: key
  } do
    for _ <- 1..20 do
      unboxed(fn ->
        project(repo, 2)
        assert Priority.set(key, 1, "first") == {:ok, 1}
      end)

      results =
        race([
          fn -> project(repo, 1) end,
          fn -> Priority.set(key, 3, "newer") end
        ])

      assert {:ok, 3} in results

      unboxed(fn ->
        assert Priority.for_keys([key])[key] == %{priority: 3, file: 1, changed_on_board: true}

        assert [%{actor: "newer", priority: 3}] =
                 Enum.filter(Priority.overrides(), &(&1.repo == repo))
      end)
    end
  end

  test "jump and dispatch serialize without leaving a jump on a dispatched ticket", %{
    repo: repo,
    key: key
  } do
    unboxed(fn -> project(repo, 2) end)

    results =
      race([
        fn -> Priority.jump(key, "user") end,
        fn -> Foreman.Overlay.apply_event(key, {:dispatch, %{window: "preview"}}) end
      ])

    assert Enum.any?(results, &match?({:ok, %{stage: :dispatched}}, &1))
    assert Enum.any?(results, &(&1 == {:ok, 0} or &1 == {:error, :not_queued}))

    unboxed(fn ->
      refute Enum.any?(Priority.pending_jumps(), &(&1.repo == repo))
      assert Foreman.Overlay.get(key).stage == :dispatched
    end)
  end

  defp project(repo, priority) do
    Projection.replace(
      repo,
      Jason.encode!(%{
        id: "a",
        title: "Race",
        status: "open",
        issue_type: "task",
        priority: priority
      })
    )
  end

  defp race(funs) do
    parent = self()

    for fun <- funs do
      start_supervised!(%{
        id: make_ref(),
        restart: :temporary,
        start:
          {Task, :start_link,
           [
             fn ->
               send(parent, {:ready, self()})

               receive do
                 :go -> send(parent, {:result, unboxed(fun)})
               end
             end
           ]}
      })
    end

    pids =
      for _ <- funs do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :go))

    for _ <- funs do
      assert_receive {:result, result}, 5000
      result
    end
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
