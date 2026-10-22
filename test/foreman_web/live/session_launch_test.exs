defmodule ForemanWeb.SessionLaunchTest do
  use ForemanWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    {:ok, config} =
      Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

    config =
      Map.put(config, "repos", [%{"key" => "sample", "path" => "/tmp/sample", "enabled" => true}])

    Foreman.Repo.insert_all("board_config", [
      %{id: 1, config: config, source: "test", discovered: [], loaded_at: DateTime.utc_now()}
    ])

    rows = [
      %{id: "x-1", title: "Unplanned", issue_type: "task", status: "open"},
      %{id: "x-2", title: "Epic", issue_type: "epic", status: "open"},
      %{
        id: "x-3",
        title: "Child",
        issue_type: "task",
        status: "open",
        dependencies: [%{depends_on_id: "x-2", type: "parent-child"}]
      }
    ]

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    Foreman.Overlay.apply_event({"sample", "draft:plan"}, {:create, %{title: "Draft plan"}})
    :ok
  end

  test "sheet offers Launch only for unplanned tickets", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?ticket=sample:x-1")
    assert has_element?(view, "#ticket-launch")
    {:ok, child, _} = live(conn, "/?ticket=sample:x-3")
    refute has_element?(child, "#ticket-launch")
  end

  test "Launch appears for drafts and ticketed epics, but not terminal epics", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#drafts [phx-click=launch-session][phx-value-ticket='draft:plan']")
    assert has_element?(view, "#epics [phx-click=launch-session][phx-value-ticket='x-2']")
    {:ok, epic, _} = live(conn, "/epics/sample/x-2")
    assert has_element?(epic, "#epic-launch", "Launch")

    for stage <- [:done, :abandoned] do
      Foreman.Repo.query!("UPDATE epics SET stage = $1 WHERE bead_id = 'x-2'", [to_string(stage)])
      send(view.pid, :reconcile)
      send(epic.pid, :reconcile)
      assert has_element?(epic, "#epic-launch") == stage in [:building, :shipping]

      assert has_element?(view, "#epics [phx-click=launch-session][phx-value-ticket='x-2']") ==
               stage in [:building, :shipping]
    end

    Foreman.Repo.query!(
      "UPDATE epics SET stage = 'idea' WHERE repo_key = 'sample' AND bead_id = 'x-2'"
    )

    send(view.pid, :reconcile)
    assert has_element?(view, "#epics [phx-click=launch-session][phx-value-ticket='x-2']")
    {:ok, detail, _} = live(conn, "/epics/sample/draft:plan")
    assert has_element?(detail, "#epic-launch")
    Foreman.Overlay.apply_event({"sample", "draft:plan"}, :start_spec)
    send(detail.pid, :reconcile)
    refute has_element?(detail, "#epic-launch")
  end

  test "file status does not depend on acceptance checkboxes, while beads keeps its prefix", %{
    conn: conn
  } do
    Foreman.Repo.query!(
      "UPDATE board_config SET config = jsonb_set(config, '{repos,0,tickets}', '\"files\"')"
    )

    {:ok, view, _} = live(conn, "/?ticket=sample:x-1")
    assert has_element?(view, "#ticket-status", "open")
    refute has_element?(view, "#ticket-status", "bd:")

    Foreman.Repo.query!(
      "UPDATE board_config SET config = jsonb_set(config, '{repos,0,tickets}', '\"beads\"')"
    )

    send(view.pid, :reconcile)
    assert has_element?(view, "#ticket-status", "bd: open")
  end

  test "live windows show Focus on sheets, details and list rows", %{conn: conn} do
    for ticket <- ["x-1", "draft:plan", "x-2"] do
      Foreman.Repo.insert!(%Foreman.PlanningSession{
        project: "sample",
        ticket: ticket,
        state: :running,
        workdir: "/tmp/sample",
        window: "@1",
        launched_at: DateTime.utc_now()
      })
    end

    {:ok, sheet, _} = live(conn, "/?ticket=sample:x-1")
    assert has_element?(sheet, "#ticket-launch", "Focus")
    assert has_element?(sheet, "#drafts [phx-click=launch-session]", "Focus")
    assert has_element?(sheet, "#epics [phx-click=launch-session]", "Focus")
    {:ok, detail, _} = live(conn, "/epics/sample/x-2")
    assert has_element?(detail, "#epic-launch", "Focus")
    Foreman.Repo.query!("UPDATE planning_sessions SET state = 'ended'")
    send(sheet.pid, :reconcile)
    assert has_element?(sheet, "#ticket-launch", "Relaunch")
    Foreman.Repo.query!("UPDATE planning_sessions SET state = 'parked'")
    send(sheet.pid, :reconcile)
    send(detail.pid, :reconcile)
    assert has_element?(sheet, "#ticket-launch[phx-value-action=relaunch]", "Relaunch")
    assert has_element?(sheet, "#drafts [phx-click=launch-session]", "Relaunch")
    assert has_element?(sheet, "#epics [phx-click=launch-session]", "Relaunch")
    assert has_element?(detail, "#epic-launch", "Relaunch")
  end

  test "building ticket Focus selects its dispatched pane, not the coordinator", %{conn: conn} do
    socket = "fm-build-focus-#{System.unique_integer([:positive])}"

    {_, 0} =
      System.cmd("tmux", [
        "-L",
        socket,
        "-f",
        "/dev/null",
        "new-session",
        "-d",
        "-s",
        "sample",
        "-n",
        "x-2",
        "cat"
      ])

    {pane, 0} =
      System.cmd("tmux", [
        "-L",
        socket,
        "split-window",
        "-d",
        "-t",
        "sample:x-2",
        "-P",
        "-F",
        ~S(#{pane_id}),
        "cat"
      ])

    pane = String.trim(pane)
    previous = Application.get_env(:foreman, :planning_tmux_socket)
    Application.put_env(:foreman, :planning_tmux_socket, socket)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:foreman, :planning_tmux_socket, previous),
        else: Application.delete_env(:foreman, :planning_tmux_socket)

      System.cmd("tmux", ["-L", socket, "kill-server"], stderr_to_stdout: true)
    end)

    assert {:ok, _} =
             Foreman.Overlay.apply_event({"sample", "x-3"}, {:dispatch, %{window: "main-build"}})

    {:ok, window_build, _} = live(conn, "/?ticket=sample:x-3")
    refute has_element?(window_build, "#ticket-build-focus")

    assert {:ok, _} = Foreman.Overlay.apply_event({"sample", "x-3"}, {:dispatch, %{window: pane}})

    assert {:ok, _} =
             Foreman.Overlay.apply_event({"sample", "x-3"}, {:progress, %{body: "Building"}})

    {:ok, view, _} = live(conn, "/?ticket=sample:x-3")
    assert has_element?(view, "#ticket-build-focus", "Focus")
    view |> element("#ticket-build-focus") |> render_click()

    assert {selected, 0} =
             System.cmd("tmux", [
               "-L",
               socket,
               "display-message",
               "-p",
               "-t",
               "sample:",
               ~S(#{pane_id})
             ])

    assert String.trim(selected) == pane
    {:ok, epic, _} = live(conn, "/epics/sample/x-2?ticket=sample:x-3")
    assert has_element?(epic, "#epic-launch", "Launch")
    assert has_element?(epic, "#ticket-build-focus", "Focus")
  end

  test "session state and copyable attach command are visible", %{conn: conn} do
    Foreman.Repo.insert!(%Foreman.PlanningSession{
      project: "sample",
      ticket: "x-1",
      state: :running,
      workdir: "/tmp/sample",
      window: "@1",
      launched_at: DateTime.utc_now()
    })

    {:ok, view, _} = live(conn, "/?ticket=sample:x-1")
    assert has_element?(view, "#ticket-planning-state", "running")
    assert has_element?(view, "#ticket-attach[value*=tmux]")
    assert has_element?(view, "#ticket-copy-attach")
  end
end
