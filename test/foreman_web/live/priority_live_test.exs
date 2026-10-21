defmodule ForemanWeb.PriorityLiveTest do
  use ForemanWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Foreman.{Repo, Priority}

  setup do
    {:ok, config} =
      Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

    config =
      Map.put(config, "repos", [
        %{"key" => "priority", "path" => "/tmp/priority", "enabled" => true}
      ])

    Repo.insert_all("board_config", [
      %{id: 1, config: config, source: "test", discovered: [], loaded_at: DateTime.utc_now()}
    ])

    rows =
      [
        %{id: "epic", issue_type: "epic", priority: 2},
        %{id: "a", priority: 4, dependencies: [%{depends_on_id: "epic", type: "parent-child"}]},
        %{id: "b", priority: 1, dependencies: [%{depends_on_id: "epic", type: "parent-child"}]}
      ]
      |> Enum.map(
        &Map.merge(
          %{title: "Priority fixture", issue_type: "task", status: "open", dependencies: []},
          &1
        )
      )

    Foreman.Beads.Projection.replace("priority", Enum.map_join(rows, "\n", &Jason.encode!/1))

    requests =
      for id <- ~w(a b) do
        Repo.insert!(%Foreman.Requests.Request{
          repo_key: "priority",
          bead_id: id,
          kind: "decision",
          actor: "pi",
          state: "pending",
          facts: %{"question" => "Which?", "options" => ["One", "Two"]}
        })
      end

    {:ok, requests: requests}
  end

  defp ids(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-bead]")
    |> LazyHTML.attribute("data-bead")
  end

  test "Initiatives sorts effective priority and edits the sheet", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?view=")
    epic = Base.url_encode64("priority/epic", padding: false)
    view |> element("#toggle-" <> epic) |> render_click()
    assert ids(view, "#epics") == ["epic", "b", "a"]
    assert has_element?(view, "[data-bead=a] [data-priority='4']", "P4")
    view |> element("[data-bead=a] a.bb-ticket") |> render_click()
    assert has_element?(view, "#ticket-priority [data-priority='4']", "P4")
    view |> form("#ticket-priority-form", %{"priority" => "0"}) |> render_change()
    assert Priority.for_keys([{"priority", "a"}])[{"priority", "a"}].priority == 0
    assert has_element?(view, "#ticket-priority [data-priority='0']", "P0")
    assert ids(view, "#epics") == ["epic", "a", "b"]
    render_hook(view, "priority", %{"priority" => %{}})
    assert has_element?(view, "#ticket-priority [data-priority='0']", "P0")
    view |> element("#ticket-jump") |> render_click()
    assert [%{id: "a"}] = Priority.pending_jumps()
  end

  test "Standalone and Unplanned order priority before their existing age tie-breaker", %{
    conn: conn
  } do
    rows =
      [
        %{id: "a", priority: 4, created_at: "2026-10-20T00:00:00Z"},
        %{id: "b", priority: 1, created_at: "2026-10-19T00:00:00Z"},
        %{id: "new", priority: 4, created_at: "2026-10-20T00:00:00Z"},
        %{id: "old", priority: 1, created_at: "2026-10-19T00:00:00Z"}
      ]
      |> Enum.map(
        &Map.merge(
          %{title: "Priority fixture", issue_type: "task", status: "open", dependencies: []},
          &1
        )
      )

    Foreman.Beads.Projection.replace("priority", Enum.map_join(rows, "\n", &Jason.encode!/1))
    {:ok, view, _} = live(conn, "/?view=")
    view |> element("#toggle-standalone") |> render_click()
    view |> element("#toggle-standalone-project-priority") |> render_click()
    view |> element("#toggle-unplanned") |> render_click()
    view |> element("#toggle-project-priority") |> render_click()
    assert ids(view, "#standalone") == ["b", "a"]
    assert ids(view, "#unplanned") == ["old", "new"]
    Priority.set({"priority", "a"}, 0, "user")
    Priority.set({"priority", "new"}, 0, "user")
    send(view.pid, :reconcile)
    assert ids(view, "#standalone") == ["a", "b"]
    assert ids(view, "#unplanned") == ["new", "old"]
  end

  test "Needs you starts ordered and refreshes badges after a board edit", %{
    conn: conn,
    requests: [a, b]
  } do
    {:ok, view, _} = live(conn, "/needs-you")
    assert request_ids(view) == [b.id, a.id]
    assert has_element?(view, "#request-#{a.id} [data-priority='4']", "P4")
    Priority.set({"priority", "a"}, 0, "user")
    send(view.pid, :reconcile)
    assert has_element?(view, "#request-#{a.id} [data-priority='0']", "P0")
  end

  defp request_ids(view) do
    view
    |> element("#pending-requests")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("article")
    |> LazyHTML.attribute("id")
    |> Enum.map(&String.replace_prefix(&1, "request-", ""))
  end
end
