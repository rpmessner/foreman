defmodule Foreman.PriorityTest do
  use Foreman.DataCase, async: false
  alias Foreman.{Priority, Beads.Projection}

  defp project(priority) do
    Projection.replace(
      "priority",
      Jason.encode!(%{
        id: "a",
        title: "A",
        issue_type: "task",
        status: "open",
        priority: priority,
        dependencies: []
      })
    )
  end

  test "overlay ls exposes filtered overrides and jumps with effective priorities" do
    project(2)
    Priority.jump({"priority", "a"}, "user")

    assert {200, body} =
             Foreman.AgentCommands.execute(%{"action" => "ls", "project" => "priority"})

    assert [%{repo: "priority", id: "a", stage: "queued"}] = body.items
    assert [%{repo: "priority", id: "a", priority: 0, file_priority: 2}] = body.priority_overrides
    assert [%{repo: "priority", id: "a"}] = body.jumps

    assert {200, %{items: [], priority_overrides: [], jumps: []}} =
             Foreman.AgentCommands.execute(%{"action" => "ls", "project" => "other"})
  end

  test "effective order respects priority then jumps ahead of its band" do
    rows =
      for {id, priority} <- [{"a", 2}, {"b", 1}, {"c", 0}, {"d", 3}],
          do: %{
            id: id,
            priority: priority,
            title: id,
            issue_type: "task",
            status: "open",
            dependencies: []
          }

    Projection.replace("priority", Enum.map_join(rows, "\n", &Jason.encode!/1))
    keys = Enum.map(~w(a b c d), &{"priority", &1})
    assert Priority.set({"priority", "d"}, 1, "user") == {:ok, 1}
    items = Enum.map(keys, &%{key: &1})
    assert Enum.map(Priority.sort(items), & &1.key) == Enum.map(~w(c b d a), &{"priority", &1})
    assert Priority.jump({"priority", "a"}, "user") == {:ok, 0}
    assert Enum.map(Priority.sort(items), & &1.key) == Enum.map(~w(a c b d), &{"priority", &1})
  end

  test "jump sets P0 and stays pending only until the next dispatch" do
    project(2)
    key = {"priority", "a"}
    assert Priority.jump(key, "user") == {:ok, 0}
    assert Priority.for_keys([key])[key].priority == 0
    assert [%{repo: "priority", id: "a", actor: "user"}] = Priority.pending_jumps()
    assert {:ok, _} = Foreman.Overlay.apply_event(key, {:dispatch, %{window: "test"}})
    assert Priority.pending_jumps() == []
    assert Priority.jump(key, "user") == {:error, :not_queued}
    assert {:ok, _} = Foreman.Overlay.apply_event(key, :abandon)
    assert {:ok, _} = Foreman.Overlay.apply_event(key, :revive)
    assert Priority.pending_jumps() == []
  end

  test "overrides stay repository-scoped and missing projections do not leak into overlay lists" do
    project(2)

    Projection.replace(
      "another",
      Jason.encode!(%{id: "a", title: "Other", issue_type: "task", status: "open", priority: 4})
    )

    Priority.set({"priority", "a"}, 0, "user")

    assert Priority.for_keys([{"another", "a"}]) == %{
             {"another", "a"} => %{priority: 4, file: 4, changed_on_board: false}
           }

    Projection.replace("priority", "")
    assert Priority.overrides() == []
    assert Priority.for_keys([{"priority", "a"}]) == %{}
    assert Priority.set({"missing", "a"}, 0, "user") == {:error, :not_found}
  end

  test "set, change and sync preserve file ownership" do
    project(2)
    key = {"priority", "a"}
    assert Priority.set(key, 0, "user") == {:ok, 0}
    assert Priority.for_keys([key])[key] == %{priority: 0, file: 2, changed_on_board: true}
    assert Priority.set(key, 1, "user") == {:ok, 1}
    project(3)
    assert Priority.for_keys([key])[key].priority == 1
    project(1)
    assert Priority.for_keys([key])[key] == %{priority: 1, file: 1, changed_on_board: false}
    assert Priority.overrides() == []
    assert Priority.set(key, 4, "user") == {:ok, 4}
    assert Priority.set(key, 1, "user") == {:ok, 1}
    assert Priority.overrides() == []
    assert Priority.set(key, 5, "user") == {:error, :invalid_priority}
  end
end
