defmodule ForemanWeb.InitiativesLiveTest do
  use ForemanWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    {:ok, config} =
      Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

    root = Foreman.ScratchDocs.dir("initiatives")

    Foreman.ScratchDocs.write(root, %{
      "docs/spec.md" => "# Spec",
      "docs/brief.md" => "# Brief",
      "docs/report.md" => "# Report"
    })

    on_exit(fn -> File.rm_rf!(root) end)

    config =
      Map.put(config, "repos", [%{"key" => "sample", "path" => root, "enabled" => true}])

    Foreman.Repo.insert_all("board_config", [
      %{
        id: 1,
        config: config,
        source: "/tmp/settings",
        discovered: [],
        loaded_at: DateTime.utc_now()
      }
    ])

    rows = [
      b("e", "epic"),
      b("a", "task", [%{depends_on_id: "e", type: "parent-child"}], "closed"),
      Map.put(b("f", "bug", [%{depends_on_id: "a", type: "discovered-from"}]), :labels, [
        "follow-up"
      ]),
      b("o", "chore")
    ]

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    :ok
  end

  test "on hold tickets have their own section, retain epic membership, and never become stale",
       %{conn: conn} do
    rows = [
      b("e", "epic"),
      b("free", "task"),
      b("child", "task", [%{depends_on_id: "e", type: "parent-child"}])
    ]

    rows =
      Enum.map(rows, fn row ->
        if row.id == "e",
          do: row,
          else:
            Map.merge(row, %{
              status: "on_hold",
              on_hold_reason: "Awaiting parts",
              on_hold_since: "2026-10-21T00:00:00Z"
            })
      end)

    assert {:ok, _} =
             Foreman.Beads.Projection.replace(
               "sample",
               Enum.map_join(rows, "\n", &Jason.encode!/1)
             )

    Foreman.Overlay.apply_event({"sample", "free"}, {:dispatch, %{window: "old"}})
    Foreman.Overlay.apply_event({"sample", "child"}, {:dispatch, %{window: "old"}})
    Foreman.Overlay.apply_event({"sample", "child"}, {:progress, %{body: "Paused"}})
    Foreman.Repo.update_all("sessions", set: [last_seen_at: ~N[2020-01-01 00:00:00]])
    snapshot = Foreman.Initiatives.snapshot(%{"view" => "open"})
    assert Enum.map(Map.get(snapshot, :on_hold, []), & &1.id) |> Enum.sort() == ~w(child free)
    assert snapshot.orphans == []
    assert snapshot.standalone == []
    assert [%{planned: [%{id: "child", stale: false}]}] = snapshot.epics
    assert Enum.all?(snapshot.on_hold, &(not &1.stale))
    stale = Foreman.Initiatives.snapshot(%{"view" => "stale"})
    assert stale.on_hold == []
    assert stale.epics == []
    assert stale.standalone == []
    assert stale.orphans == []

    assert Foreman.Initiatives.snapshot(%{"view" => "open", "status" => "on_hold"}).on_hold
           |> length() == 2

    assert Foreman.Initiatives.snapshot(%{"view" => "open", "q" => "absent"}).on_hold == []
    assert %{key: {"sample", "free"}} = Foreman.Sessions.target({"sample", "free"})
    {:ok, view, _} = live(conn, "/?view=open")
    assert has_element?(view, "#on-hold-panel", "On hold")
    view |> element("#toggle-on-hold") |> render_click()
    view |> element("#toggle-on-hold-project-sample") |> render_click()
    assert ids(view, "#on-hold [data-bead]") |> Enum.sort() == ~w(child free)
    assert has_element?(view, "#on-hold [data-bead=free] [data-ticket-status=on_hold]", "On hold")
    assert has_element?(view, "#on-hold [data-bead=free]", "Awaiting parts")
    assert has_element?(view, "#on-hold [data-bead=child] [data-hold-epic=e]")

    assert has_element?(
             view,
             "#on-hold [data-bead=free] [data-hold-since] time[datetime='2026-10-21T00:00:00Z']"
           )

    refute has_element?(view, "#on-hold [data-bead=free]", "parked")
  end

  test "on hold epics navigate to their board and badges stay human readable", %{conn: conn} do
    rows =
      Enum.map(
        [b("e", "epic"), b("child", "task", [%{depends_on_id: "e", type: "parent-child"}])],
        &Map.merge(&1, %{status: "on_hold", on_hold_reason: "Awaiting review"})
      )

    assert {:ok, _} =
             Foreman.Beads.Projection.replace(
               "sample",
               Enum.map_join(rows, "\n", &Jason.encode!/1)
             )

    {:ok, view, _} = live(conn, "/?view=open")
    view |> element("#toggle-on-hold") |> render_click()
    view |> element("#toggle-on-hold-project-sample") |> render_click()

    assert has_element?(
             view,
             "#on-hold [data-bead=e] a[data-phx-link=redirect][href^='/epics/sample/e']"
           )

    {:ok, board, _} = live(conn, "/epics/sample/e")
    assert has_element?(board, "#epic-title")
    refute has_element?(board, "main", "on_hold")
    assert has_element?(board, "main", "On hold")
    assert Foreman.Drilldown.epic({"sample", "e"}).total == 1
  end

  test "sheet labels ticket hold separately from planning session state and shows its reason", %{
    conn: conn
  } do
    row =
      Map.merge(b("held", "task"), %{
        status: "on_hold",
        on_hold_reason: "Awaiting parts",
        on_hold_since: "2026-10-21T00:00:00Z"
      })

    assert {:ok, _} = Foreman.Beads.Projection.replace("sample", Jason.encode!(row))
    {:ok, view, _} = live(conn, "/?view=open&ticket=sample:held")
    assert has_element?(view, "#ticket-status", "On hold")
    assert has_element?(view, "#ticket-on-hold-reason", "Awaiting parts")
    assert has_element?(view, "#ticket-on-hold-since time[title='2026-10-21T00:00:00Z']")
  end

  test "parentless tickets with board activity are standalone, including ended sessions and requests",
       %{conn: conn} do
    rows =
      Enum.map(~w(untouched staged session requested), fn id ->
        b(id, "task", [], if(id == "untouched", do: "in_progress", else: "open"))
      end)

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    Foreman.Overlay.apply_event({"sample", "staged"}, {:dispatch, %{window: "test"}})
    now = DateTime.utc_now()

    Foreman.Repo.insert_all("sessions", [
      %{
        repo_key: "sample",
        bead_id: "session",
        window: "old",
        started_at: now,
        last_seen_at: now,
        ended_at: now
      }
    ])

    Foreman.Repo.insert!(%Foreman.Requests.Request{
      repo_key: "sample",
      bead_id: "requested",
      kind: "decision",
      actor: "pi",
      state: "answered",
      facts: %{},
      outcome: %{}
    })

    snapshot = Foreman.Initiatives.snapshot(%{"view" => ""})
    assert Enum.map(snapshot.orphans, & &1.id) == ["untouched"]
    assert Enum.map(snapshot.standalone, & &1.id) |> Enum.sort() == ~w(requested session staged)
    {:ok, view, _} = live(conn, "/?view=")
    assert has_element?(view, "#standalone-panel", "Standalone work")
    view |> element("#toggle-standalone") |> render_click()
    view |> element("#toggle-standalone-project-sample") |> render_click()
    assert ids(view, "#standalone [data-bead]") |> Enum.sort() == ~w(requested session staged)
    view |> element("#toggle-unplanned") |> render_click()
    view |> element("#toggle-project-sample") |> render_click()
    assert ids(view, "#unplanned [data-bead]") == ["untouched"]
  end

  test "In flight includes standalone work waiting on a request before dispatch", %{conn: conn} do
    Foreman.Repo.insert!(%Foreman.Requests.Request{
      repo_key: "sample",
      bead_id: "o",
      kind: "decision",
      actor: "pi",
      state: "answered",
      facts: %{},
      outcome: %{}
    })

    assert [%{id: "o"}] = Foreman.Initiatives.snapshot(%{"view" => "in-flight"}).standalone
    {:ok, view, _} = live(conn, "/?view=in-flight")
    view |> element("#toggle-standalone") |> render_click()
    view |> element("#toggle-standalone-project-sample") |> render_click()
    assert has_element?(view, "#standalone [data-bead=o]")

    assert Foreman.Initiatives.snapshot(%{"view" => "in-flight", "q" => "absent"}).standalone ==
             []
  end

  test "ended planning conversations keep parentless work out of Unplanned", %{conn: conn} do
    Foreman.Repo.insert!(%Foreman.PlanningSession{
      project: "sample",
      ticket: "o",
      state: :ended,
      workdir: System.tmp_dir!(),
      launched_at: DateTime.utc_now()
    })

    snapshot = Foreman.Initiatives.snapshot(%{"view" => ""})
    assert snapshot.orphans == []
    assert [%{id: "o"}] = snapshot.standalone
    assert %{key: {"sample", "o"}} = Foreman.Sessions.target({"sample", "o"})
    {:ok, view, _} = live(conn, "/?view=")
    view |> element("#toggle-standalone") |> render_click()
    view |> element("#toggle-standalone-project-sample") |> render_click()
    assert has_element?(view, "#standalone [data-bead=o]")
  end

  test "planned tickets show their creation age when the epic expands", %{conn: conn} do
    rows = [
      b("e", "epic"),
      Map.put(
        b("child", "task", [%{depends_on_id: "e", type: "parent-child"}]),
        :created_at,
        "2020-01-01T00:00:00Z"
      )
    ]

    assert {:ok, _} =
             Foreman.Beads.Projection.replace(
               "sample",
               Enum.map_join(rows, "\n", &Jason.encode!/1)
             )

    {:ok, view, _} = live(conn, "/?view=")
    view |> element("#epics [data-bead=e] button[phx-click=toggle]") |> render_click()

    assert has_element?(
             view,
             "#epics [data-bead=child] time[datetime='2020-01-01T00:00:00Z'][title='2020-01-01T00:00:00Z']"
           )

    assert Foreman.Initiatives.snapshot(%{"view" => ""}).orphans == []
  end

  test "past stage activity stays standalone after revival without a session", %{conn: conn} do
    Foreman.Overlay.apply_event({"sample", "o"}, :abandon)
    Foreman.Overlay.apply_event({"sample", "o"}, :revive)
    snapshot = Foreman.Initiatives.snapshot(%{"view" => ""})
    assert snapshot.orphans == []
    assert [%{id: "o", stage: :queued}] = snapshot.standalone
    assert %{key: {"sample", "o"}} = Foreman.Sessions.target({"sample", "o"})
    {:ok, view, _} = live(conn, "/?view=")
    view |> element("#toggle-standalone") |> render_click()
    view |> element("#toggle-standalone-project-sample") |> render_click()
    assert has_element?(view, "#standalone [data-bead=o]")
  end

  test "Unplanned is newest first with unknown dates last and shared human ages", %{conn: conn} do
    recent = DateTime.utc_now() |> DateTime.add(-172_800, :second) |> DateTime.truncate(:second)

    rows = [
      Map.put(b("a-old", "task"), :created, "2020-01-01"),
      Map.put(b("z-new", "task"), :created_at, DateTime.to_iso8601(recent)),
      Map.put(b("bad", "task"), :created, "invalid"),
      b("missing", "task")
    ]

    assert {:ok, _} =
             Foreman.Beads.Projection.replace(
               "sample",
               Enum.map_join(rows, "\n", &Jason.encode!/1)
             )

    snapshot = Foreman.Initiatives.snapshot(%{"view" => ""})
    assert Enum.map(snapshot.orphans, & &1.id) == ~w(z-new a-old bad missing)
    assert Enum.find(snapshot.orphans, &(&1.id == "a-old")).created_at == ~U[2020-01-01 00:00:00Z]
    {:ok, view, _} = live(conn, "/?view=")
    view |> element("#toggle-unplanned") |> render_click()
    view |> element("#toggle-project-sample") |> render_click()
    assert ids(view, "#unplanned [data-bead]") == ~w(z-new a-old bad missing)

    assert has_element?(
             view,
             "#unplanned [data-bead=z-new] time[datetime='#{DateTime.to_iso8601(recent)}'][title='#{DateTime.to_iso8601(recent)}']",
             "2 d ago"
           )

    refute has_element?(view, "#unplanned [data-bead=bad] time")
    refute has_element?(view, "#unplanned [data-bead=missing] time")
  end

  test "the global coordinator offers state, focus, resume and a separate fresh start", %{
    conn: conn
  } do
    {:ok, _, :adopt} = Foreman.Sessions.prepare_coordinator({:adopt, Ecto.UUID.generate()})
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#coordinator-state", "ended")
    assert has_element?(view, "#coordinator-focus")
    assert has_element?(view, "#coordinator-relaunch")
    assert has_element?(view, "#coordinator-fresh[data-confirm]")
  end

  test "an idle coordinator shows waiting on its row with nothing in Needs you", %{conn: conn} do
    {:ok, s, :fresh} = Foreman.Sessions.prepare_coordinator(:resume, window: "@123")
    {:waiting, facts} = Foreman.SessionHooks.facts("Stop", %{})

    {:ok, _} =
      Foreman.SessionWaiting.ask(Foreman.Sessions.coordinator_key(), %{
        "session" => s.session_id,
        "facts" => facts
      })

    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#coordinator-state", "waiting")
    refute has_element?(view, "#needs-you-count")
  end

  test "sheet preview is explicit and exposes running URL, logs and stop", %{conn: conn} do
    key = {"sample", "f"}

    Foreman.Overlay.apply_event(
      key,
      {:dispatch, %{window: "preview", workdir: System.tmp_dir!()}}
    )

    {:ok, view, _} = live(conn, "/?ticket=sample:f")
    assert has_element?(view, "#preview-start")
    assert Foreman.Previews.for_ticket(key).state == :none
    view |> element("#preview-start") |> render_click()
    assert has_element?(view, "#preview-state", "starting")
    Foreman.Previews.reconcile(Foreman.FakeDevserve)
    send(view.pid, :reconcile)
    assert has_element?(view, "#preview-open[href='http://127.0.0.1:4888']")
    assert has_element?(view, "#preview-logs", "Listening on localhost")
    view |> element("#preview-stop") |> render_click()
    assert Foreman.Previews.for_ticket(key).state == :stopping
  end

  test "ticket sections render Markdown and disabled acceptance checkboxes", %{conn: conn} do
    raw =
      b("markdown", "task")
      |> Map.merge(%{
        description: "## Reader\n\n[Spec](docs/spec.md)\n\n<script>alert(1)</script>",
        acceptance_criteria: "- [x] Complete\n- [ ] Pending",
        design: "**Design**"
      })

    Foreman.Beads.Projection.replace("sample", Jason.encode!(raw))
    {:ok, view, _} = live(conn, "/?ticket=sample:markdown")
    assert has_element?(view, "#ticket-overview .fm-markdown h2", "Reader")
    assert has_element?(view, "#ticket-overview input[type=checkbox][disabled][checked]")
    assert has_element?(view, "#ticket-overview a[href='/documents/sample?path=docs%2Fspec.md']")
    refute has_element?(view, "#ticket-overview script")
  end

  test "ticket sheet links every history payload value and lists documents without a note", %{
    conn: conn
  } do
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "docs"}})

    Foreman.Overlay.apply_event(
      {"sample", "f"},
      {:progress, %{body: "Read docs/report.md", evidence: %{"nested" => "docs/spec.md"}}}
    )

    Foreman.Repo.insert!(%Foreman.Requests.Request{
      repo_key: "sample",
      bead_id: "f",
      kind: "decision",
      actor: "pi",
      state: "answered",
      facts: %{"question" => "Read docs/brief.md"},
      outcome: %{"answer" => "Use docs/spec.md"}
    })

    {:ok, view, _} = live(conn, "/?ticket=sample:f")

    assert has_element?(
             view,
             "#ticket-documents a[href='/documents/sample?path=docs%2Fbrief.md']"
           )

    assert has_element?(
             view,
             "#ticket-documents a[href='/documents/sample?path=docs%2Freport.md']"
           )

    assert has_element?(view, "#ticket-documents a[href='/documents/sample?path=docs%2Fspec.md']")
    assert has_element?(view, "#ticket-documents", "main checkout")
    assert has_element?(view, "#ticket-history a[href='/documents/sample?path=docs%2Freport.md']")
    assert has_element?(view, "#ticket-history a[href='/documents/sample?path=docs%2Fspec.md']")
  end

  test "overview omits absent fields and empty relationship sections", %{conn: conn} do
    raw =
      b("empty", "task") |> Map.merge(%{close_reason: nil, labels: [], closed_at: nil, notes: ""})

    Foreman.Beads.Projection.replace("sample", Jason.encode!(raw))
    {:ok, view, _} = live(conn, "/?ticket=sample:empty")
    refute has_element?(view, "#ticket-overview dt", "close reason")
    refute has_element?(view, "#ticket-overview dt", "labels")
    refute has_element?(view, "#ticket-overview dt", "closed at")
    refute has_element?(view, "#ticket-documents")
    refute has_element?(view, "#ticket-overview h3", "Dependencies")
    refute has_element?(view, "#ticket-overview h3", "Linked CRs")
  end

  test "file ticket supersedes appears on the sheet even when its target is absent", %{conn: conn} do
    root = Path.join(System.tmp_dir!(), "fm-sheet-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "tickets"))
    {_, 0} = System.cmd("git", ["init", "-q", root])
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "tickets/demo-new.md"), """
    ---
    id: demo-new
    title: Replacement
    type: chore
    status: open
    priority: 2
    parent: null
    blocked_by: []
    related: []
    supersedes: [demo-old]
    discovered_from: null
    labels: []
    created: 2026-10-18
    closed: null
    close_reason: null
    ---
    """)

    {:ok, snapshot} = Foreman.TicketFiles.snapshot(root)
    {[raw], []} = Foreman.TicketFiles.decode(snapshot, [])
    Foreman.Beads.Projection.replace("sample", Jason.encode!(raw))
    {:ok, view, _} = live(conn, "/?ticket=sample:demo-new")
    assert has_element?(view, "#ticket-overview span", "supersedes · demo-old")
  end

  test "file ticket acceptance shows checked and total", %{conn: conn} do
    raw =
      b("progress", "task")
      |> Map.put(:acceptance_progress, %{"checked" => 1, "total" => 3})
      |> Map.put(:created_at, "2026-10-18T00:00:00Z")

    Foreman.Beads.Projection.replace("sample", Jason.encode!(raw))
    {:ok, view, _} = live(conn, "/?ticket=sample:progress")
    assert has_element?(view, "#ticket-acceptance-progress", "1/3")
    assert has_element?(view, "#ticket-overview time[datetime='2026-10-18T00:00:00Z']")
  end

  test "sheet tab is selected from valid, unknown and missing URL params", %{conn: conn} do
    for {query, selected} <- [
          {"", "overview"},
          {"&tab=history", "history"},
          {"&tab=sessions", "sessions"},
          {"&tab=notes", "notes"},
          {"&tab=unknown", "overview"},
          {"&tab[]=history", "overview"}
        ] do
      {:ok, view, _} = live(conn, "/?ticket=sample:f" <> query)
      assert has_element?(view, "#ticket-#{selected}-tab[aria-selected=true]")
      assert has_element?(view, "#ticket-#{selected}-panel:not([hidden])")
      assert has_element?(view, "#ticket-overview h3")

      for section <- ~w(history sessions notes) do
        refute has_element?(view, "#ticket-#{section}-section > h3")
      end

      for other <- ~w(overview history sessions notes) -- [selected] do
        assert has_element?(view, "#ticket-#{other}-panel[hidden]")
      end
    end
  end

  test "tab patches retain ticket and all filters, close clears sheet params", %{conn: conn} do
    {:ok, view, _} =
      live(
        conn,
        "/?ticket=sample:f&project=sample&type=bug&label=follow-up&status=open&stale=true&q=f"
      )

    view |> element("#ticket-history-tab") |> render_click()
    params = URI.decode_query(URI.parse(assert_patch(view)).query)

    assert params == %{
             "ticket" => "sample:f",
             "tab" => "history",
             "project" => "sample",
             "type" => "bug",
             "label" => "follow-up",
             "status" => "open",
             "stale" => "true",
             "q" => "f"
           }

    assert has_element?(view, "#ticket-history-panel:not([hidden])")
    view |> element("#ticket-close") |> render_click()
    closed = URI.decode_query(URI.parse(assert_patch(view)).query)
    assert closed == Map.drop(params, ["ticket", "tab"])
  end

  test "hidden streams update before switching tabs", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?ticket=sample:f")
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "tab-worker"}})

    Foreman.Overlay.apply_event(
      {"sample", "f"},
      {:report, %{body: "Fresh tab report", path: "docs/report.md"}}
    )

    send(view.pid, {:notification, :foreman_events, "sample/f"})
    assert has_element?(view, "#ticket-history-panel[hidden] #ticket-history", "dispatch")
    assert has_element?(view, "#ticket-sessions-panel[hidden] #ticket-sessions", "tab-worker")
    assert has_element?(view, "#ticket-notes-panel[hidden] #ticket-notes", "Fresh tab report")

    for {tab, content} <- [
          {"history", "dispatch"},
          {"sessions", "tab-worker"},
          {"notes", "Fresh tab report"}
        ] do
      view |> element("#ticket-#{tab}-tab") |> render_click()
      assert_patch(view)
      assert has_element?(view, "#ticket-#{tab}-panel:not([hidden])", content)
    end
  end

  test "ticket rows open a URL sheet and closing retains filters and expansion", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?project=sample&type=bug")
    view |> element("[data-bead=e] button") |> render_click()
    view |> element("[data-bead=f] a") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["ticket"] == "sample:f"
    assert has_element?(view, "#ticket-sheet[data-open=true]")
    assert has_element?(view, "#ticket-title", "f")
    assert has_element?(view, "#ticket-actions")
    view |> element("#ticket-close") |> render_click()
    closed = assert_patch(view)
    assert URI.decode_query(URI.parse(closed).query)["type"] == "bug"
    refute has_element?(view, "#ticket-sheet[data-open=true]")
    assert has_element?(view, "[data-bead=f]")
  end

  test "direct sheet URLs and live updates retain their underlying page", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?ticket=sample:f&project=sample")
    assert has_element?(view, "#ticket-stage", "queued")
    Foreman.Overlay.apply_event({"sample", "f"}, :review)
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "worker"}})
    send(view.pid, {:notification, :foreman_events, "sample/f"})
    assert has_element?(view, "#ticket-stage", "dispatched")
    assert has_element?(view, "#ticket-history [data-outcome=invalid]", "review")
    assert has_element?(view, "#ticket-sessions", "worker")
    render_patch(view, "/?project=sample")
    refute has_element?(view, "#ticket-sheet[data-open=true]")
    render_patch(view, "/?ticket=sample:f&project=sample")
    assert has_element?(view, "#ticket-sheet[data-open=true]")
  end

  test "epic route shows columns, fallout, history and opens a sheet", %{conn: conn} do
    {:ok, view, _} = live(conn, "/epics/sample/e?type=bug")
    assert has_element?(view, "#epic-title", "e")
    assert has_element?(view, "#epic-history", "backfill")
    assert has_element?(view, "[data-band=planned] [data-ticket=a]")
    assert has_element?(view, "[data-band=fallout] [data-ticket=f]")
    view |> element("[data-band=fallout] [data-ticket=f]") |> render_click()
    assert_patch(view, "/epics/sample/e?ticket=sample%3Af&type=bug")
    assert has_element?(view, "#ticket-sheet[data-open=true]")
    view |> element("#ticket-close") |> render_click()
    assert_patch(view, "/epics/sample/e?type=bug")
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "worker"}})
    send(view.pid, {:notification, :foreman_events, "sample/f"})
    assert has_element?(view, "[data-band=fallout] [data-stage=dispatched]")
  end

  test "epic title navigation carries filters and missing routes stay usable", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?project=sample&type=bug")
    view |> element("[data-bead=e] a") |> render_click()
    assert_redirect(view, "/epics/sample/e?project=sample&type=bug")
    {:ok, missing, _} = live(conn, "/epics/sample/missing?ticket[]=bad")
    assert has_element?(missing, "#epic-not-found")
    refute has_element?(missing, "#ticket-sheet[data-open=true]")
  end

  test "epic config and own history refresh while a sheet is open", %{conn: conn} do
    {:ok, view, _} = live(conn, "/epics/sample/e?ticket=sample:f")

    config =
      Foreman.RuntimeState.config().config
      |> Map.put("columns", [%{"title" => "Everything", "stages" => ["queued", "done"]}])

    Foreman.Repo.query!("UPDATE board_config SET config = $1", [config])
    Foreman.Overlay.apply_event({"sample", "e"}, :bead_epic_closed)
    send(view.pid, {:notification, :foreman_events, "sample/e"})
    assert has_element?(view, "#epic-columns h3", "Everything")
    assert has_element?(view, "#epic-history", "bead_epic_closed")
    assert has_element?(view, "#ticket-sheet[data-open=true]")

    rows =
      Foreman.Beads.Projection.list_raw("sample")
      |> Enum.map(fn raw ->
        if raw["id"] == "f", do: Map.put(raw, "title", "Updated fallout"), else: raw
      end)

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    send(view.pid, {:notification, :foreman_events, "sample"})
    assert has_element?(view, "#ticket-title", "Updated fallout")
    assert has_element?(view, "[data-ticket=f]", "Updated fallout")
  end

  test "a late close callback cannot dismiss a different selected ticket", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?ticket=sample:f")
    render_patch(view, "/?ticket=sample:a")
    render_click(view, "close-ticket", %{"key" => "sample:f"})
    assert has_element?(view, "#ticket-title", "Title a")
    assert has_element?(view, "#ticket-sheet[data-open=true]")
  end

  test "history uses relative time, human payload fields and only refusal badges", %{conn: conn} do
    Foreman.Overlay.apply_event({"sample", "f"}, :review, %{actor: "reviewer"})

    Foreman.Overlay.apply_event(
      {"sample", "f"},
      {:dispatch,
       %{
         window: "worker",
         branch: "feature",
         brief_path: "docs/brief.md",
         evidence: "Additional detail"
       }},
      %{actor: "builder"}
    )

    Foreman.Overlay.apply_event(
      {"sample", "f"},
      {:report, %{path: "docs/report.md", body: "Verified result"}}
    )

    Foreman.Repo.query!(
      "UPDATE stage_events SET inserted_at = NOW() - INTERVAL '2 hours 5 seconds'"
    )

    {:ok, view, _} = live(conn, "/epics/sample/e?ticket=sample:f")
    assert has_element?(view, "#epic-history time[title][datetime]", "2 h ago")
    assert has_element?(view, "#ticket-history time[title][datetime]", "2 h ago")
    assert has_element?(view, "#ticket-sessions time[title][datetime]")
    assert has_element?(view, "#ticket-history [data-outcome=invalid]", "Refused")
    assert has_element?(view, "#ticket-history [data-outcome=row]", "feature")
    assert has_element?(view, "#ticket-history [data-outcome=row]", "docs/brief.md")
    assert has_element?(view, "#ticket-history [data-outcome=row]", "builder")
    assert has_element?(view, "#ticket-history dt", "Report")

    assert has_element?(
             view,
             "#ticket-history a[href='/documents/sample?path=docs%2Freport.md']",
             "docs/report.md"
           )

    assert has_element?(
             view,
             "#ticket-history a[href='/documents/sample?path=docs%2Fbrief.md']",
             "docs/brief.md"
           )

    assert has_element?(view, "#ticket-history dd", "Verified result")
    refute has_element?(view, "#ticket-history [data-outcome=row] [data-history-outcome]")
    assert has_element?(view, "#ticket-history dd", "Additional detail")
    refute has_element?(view, "#ticket-history", "record: session")
    refute has_element?(view, "#ticket-history", "emit: stage")
  end

  test "fallout omits empty cells and disappears after the last fallout edge is removed", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/epics/sample/e")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[data-band=fallout]")
           |> Enum.count() == 1

    rows =
      Foreman.Beads.Projection.list_raw("sample")
      |> Enum.map(fn raw ->
        if raw["id"] == "f", do: Map.put(raw, "dependencies", []), else: raw
      end)

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    send(view.pid, {:notification, :foreman_events, "sample"})
    refute has_element?(view, "[data-band=fallout]")
  end

  test "home has derived epic progress, expandable fallout and collapsed per-project orphans", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "h1", "Initiatives")
    assert has_element?(view, "a.bb-nav-active[aria-current=page]", "Initiatives")
    assert has_element?(view, "[data-bead=e]", "building")

    assert has_element?(
             view,
             "[data-bead=e] [role=progressbar][aria-valuenow='1'][aria-valuemax='2']"
           )

    refute has_element?(view, "[data-bead=f]")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "#epics h3", "Fallout")
    assert has_element?(view, "[data-bead=f]", "bug")
    assert has_element?(view, "#toggle-unplanned[aria-expanded=false]")
    view |> element("#toggle-unplanned") |> render_click()
    refute has_element?(view, "#unplanned [data-bead=o]")
    view |> element("#toggle-project-sample") |> render_click()
    assert has_element?(view, "#unplanned [data-bead=o]")
  end

  test "filtering children retains full progress and reconciliation refreshes stages", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    view |> form("#initiative-filters", filters: %{type: "bug"}) |> render_change()
    assert has_element?(view, "[data-bead=e] [role=progressbar][aria-valuemax='2']")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "[data-bead=f]")
    refute has_element?(view, "[data-bead=a]")
    Foreman.Overlay.apply_event({"sample", "f"}, {:cr_opened, %{number: 1}})
    send(view.pid, :reconcile)
    assert has_element?(view, "[data-bead=e]", "shipping")
    assert has_element?(view, "[data-bead=f]", "pr_open")
  end

  test "drafts appear above epics and filters cover status, label, project and stale", %{
    conn: conn
  } do
    Foreman.Overlay.apply_event(
      {"sample", "draft:next"},
      {:create, %{title: "Next initiative", spec_link: "docs/next.md"}}
    )

    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#drafts [data-bead='draft:next']", "idea")
    assert has_element?(view, "#drafts a[href='/documents/sample?path=docs%2Fnext.md']")
    assert has_element?(view, "#drafts-panel ~ #epics-panel")
    view |> form("#initiative-filters", filters: %{status: "closed"}) |> render_change()
    refute has_element?(view, "#drafts-panel")
    assert has_element?(view, "[data-bead=e]")
    view |> form("#initiative-filters", filters: %{status: "", stale: "true"}) |> render_change()
    refute has_element?(view, "[data-bead=e]")
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "worker"}})
    Foreman.Repo.query!("UPDATE sessions SET last_seen_at = NOW() - INTERVAL '3 hours'")
    send(view.pid, :reconcile)
    assert has_element?(view, "[data-bead=e]", "stale")

    view
    |> form("#initiative-filters", filters: %{stale: "false", label: "follow-up"})
    |> render_change()

    refute has_element?(view, "#drafts-panel")
    assert has_element?(view, "[data-bead=e]")

    view |> element("#sidebar-project-sample") |> render_click()

    assert has_element?(view, "[data-bead=e]")
  end

  test "sub-epics expand independently and contribute to parent totals", %{conn: conn} do
    rows =
      Foreman.Beads.Projection.list_raw("sample") ++
        [
          b("sub", "epic", [%{depends_on_id: "e", type: "parent-child"}]),
          b("nested", "task", [%{depends_on_id: "sub", type: "parent-child"}])
        ]

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "[data-bead=e] [aria-valuemax='3']")
    refute has_element?(view, "[data-bead=sub]")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "[data-bead=sub] [aria-valuemax='1']")
    refute has_element?(view, "[data-bead=nested]")
    view |> element("[data-bead=sub] button") |> render_click()
    assert has_element?(view, "[data-bead=nested]")
  end

  test "finished epics are in a collapsed Done group after active epics and before Unplanned", %{
    conn: conn
  } do
    rows =
      Foreman.Beads.Projection.list_raw("sample") ++
        [
          b("done.10", "epic", [], "closed"),
          b("done.2", "epic", [], "closed"),
          b("shipped", "epic"),
          b("shipped.1", "task", [%{depends_on_id: "shipped", type: "parent-child"}], "closed"),
          b("ticketed", "epic"),
          b("shipping", "epic"),
          b("shipping.1", "task", [%{depends_on_id: "shipping", type: "parent-child"}])
        ]

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    Foreman.Overlay.apply_event({"sample", "shipping.1"}, {:cr_opened, %{number: 1}})
    {:ok, view, _} = live(conn, "/?view=all")
    assert has_element?(view, "#toggle-done[aria-expanded=false]")
    assert has_element?(view, "#done-count", "3")
    assert has_element?(view, "#epics-panel + #done-panel + #standalone-panel + #unplanned-panel")
    assert ids(view, "#epics [data-kind=epic]") == ["e", "shipping", "ticketed"]
    refute has_element?(view, "[data-bead='done.2']")
    refute has_element?(view, "[data-bead=shipped]")
    view |> element("#toggle-done") |> render_click()
    assert ids(view, "#done [data-kind=epic]") == ["done.2", "done.10", "shipped"]
    assert has_element?(view, "#done [data-bead='done.2'] .bb-epic-progress", "—")
    refute has_element?(view, "#done [data-bead='done.2'] [role=progressbar]")
    view |> element("#done [data-bead=shipped] button") |> render_click()
    assert has_element?(view, "#done [data-bead='shipped.1']")
    view |> form("#initiative-filters", filters: %{q: "done.2"}) |> render_change()
    assert has_element?(view, "#done-count", "1")
    assert ids(view, "#done [data-kind=epic]") == ["done.2"]
    view |> element("#toggle-done") |> render_click()
    refute has_element?(view, "#done [data-kind=epic]")
  end

  test "observed closure and reopening move an expanded epic between active and Done", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/?view=all")
    view |> element("[data-bead=e] button") |> render_click()
    Foreman.Overlay.apply_event({"sample", "e"}, :bead_epic_closed)
    send(view.pid, :reconcile)
    refute has_element?(view, "#epics [data-bead=e]")
    assert has_element?(view, "#done-count", "1")
    view |> element("#toggle-done") |> render_click()
    assert has_element?(view, "#done [data-bead=e]")
    assert has_element?(view, "#done [data-bead=a]")
    Foreman.Overlay.apply_event({"sample", "e"}, :bead_epic_reopened)
    send(view.pid, :reconcile)
    assert has_element?(view, "#epics [data-bead=e]")
    assert has_element?(view, "#epics [data-bead=a]")
    assert has_element?(view, "#done-count", "0")
    refute has_element?(view, "#done [data-bead=e]")
  end

  test "an epic without child tickets shows a dash instead of progress", %{conn: conn} do
    rows = Foreman.Beads.Projection.list_raw("sample") ++ [b("empty", "epic")]
    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "[data-bead=empty] .bb-epic-progress", "—")
    refute has_element?(view, "[data-bead=empty] [role=progressbar]")
    refute has_element?(view, "[data-bead=empty] .bb-epic-progress", "0 / 0")
    refute has_element?(view, "[data-bead=empty] .bb-epic-progress", "%")
    assert has_element?(view, "[data-bead=e] [role=progressbar][aria-valuemax='2']")
  end

  test "persisted board-side links include cross-repo tickets without seeding beads edges", %{
    conn: conn
  } do
    config = Foreman.RuntimeState.config().config

    config =
      Map.update!(
        config,
        "repos",
        &(&1 ++ [%{"key" => "other", "path" => "/tmp/other", "enabled" => true}])
      )

    Foreman.Repo.query!("UPDATE board_config SET config = $1 WHERE id = 1", [config])
    Foreman.Beads.Projection.replace("other", Jason.encode!(b("external", "task")))

    Foreman.Repo.insert_all("epic_links", [
      %{repo_key: "other", bead_id: "external", epic_repo_key: "sample", epic_bead_id: "e"}
    ])

    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "[data-bead=e] [aria-valuemax='3']")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "[data-bead=external]", "Title external")
    assert [%{"dependencies" => []}] = Foreman.Beads.Projection.list_raw("other")
  end

  test "URL filters populate controls and changes patch a shareable URL", %{conn: conn} do
    {:ok, view, _} =
      live(conn, "/?project=sample&type=bug&label=follow-up&status=open&q=Title&stale=false")

    assert has_element?(view, "#filters_type option[value=bug][selected]")
    assert has_element?(view, "#sidebar-project-sample.bb-nav-active")
    assert has_element?(view, "#filters_q[value=Title]")
    view |> form("#initiative-filters", filters: %{q: "a & b"}) |> render_change()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["q"] == "a & b"
    assert URI.decode_query(URI.parse(path).query)["type"] == "bug"
  end

  test "returning from Settings restores this browser's filters", %{conn: conn} do
    remembered = %{
      "project" => "sample",
      "type" => "bug",
      "label" => "follow-up",
      "status" => "open",
      "q" => "Title",
      "stale" => "false"
    }

    {:ok, settings, _} = live(conn, "/settings")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             settings |> element("a", "Initiatives") |> render_click()

    {:ok, view, _} = live(put_connect_params(conn, %{"initiative_filters" => remembered}), "/")
    assert has_element?(view, "#filters_type option[value=bug][selected]")

    for {key, value} <- Map.drop(remembered, ["q", "stale", "project"]) do
      assert has_element?(view, "#filters_#{key} option[value='#{value}'][selected]")
    end

    assert has_element?(view, "#initiative-filter-memory[data-filters]")
    render_patch(view, "/")
    refute has_element?(view, "#sidebar-project-sample.bb-nav-active")
    assert has_element?(view, "#filters_type option[value=''][selected]")
  end

  test "explicit URLs override remembered filters, including an explicit clear", %{conn: conn} do
    conn =
      put_connect_params(conn, %{
        "initiative_filters" => %{"project" => "sample", "type" => "bug"}
      })

    {:ok, view, _} = live(conn, "/?project=")
    refute has_element?(view, "#sidebar-project-sample.bb-nav-active")
    assert has_element?(view, "#filters_type option[value=''][selected]")
  end

  test "malformed and unknown URL values fall back to defaults", %{conn: conn} do
    {:ok, view, _} =
      live(conn, "/?project[]=sample&type=invalid&label[bad]=x&status=no&stale=yes&q[]=bad")

    for key <- ~w(type label status) do
      assert has_element?(view, "#filters_#{key} option[value=''][selected]")
    end

    assert has_element?(view, "#filters_q[value='']")
    refute has_element?(view, "#filters_stale[checked]")
    assert has_element?(view, "[data-bead=e]")
  end

  test "sidebar project patches and toggles without losing other filters or counts", %{conn: conn} do
    {:ok, view, _} = live(conn, "/?type=bug")
    assert has_element?(view, "#sidebar-project-sample", "4")
    view |> element("#sidebar-project-sample") |> render_click()
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["project"] == "sample"
    assert has_element?(view, "#sidebar-project-sample.bb-nav-active[aria-current=true]")
    assert has_element?(view, "#filters_type option[value=bug][selected]")
    assert has_element?(view, "#sidebar-project-sample", "4")
    view |> element("#sidebar-project-sample") |> render_click()
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["project"] == ""
    refute has_element?(view, "#sidebar-project-sample.bb-nav-active")
    assert has_element?(view, "#filters_type option[value=bug][selected]")
  end

  test "Settings sidebar navigates to an explicit project filter", %{conn: conn} do
    {:ok, view, _} = live(conn, "/settings")
    assert has_element?(view, "#sidebar-project-sample", "4")

    assert {:error, {:live_redirect, %{to: path}}} =
             view |> element("#sidebar-project-sample") |> render_click()

    assert URI.decode_query(URI.parse(path).query)["project"] == "sample"
    {:ok, initiatives, _} = live(conn, path)
    assert has_element?(initiatives, "#sidebar-project-sample.bb-nav-active")
  end

  test "initial URL filters exclude nonmatching streamed rows", %{conn: conn} do
    Foreman.Beads.Projection.replace(
      "sample",
      Enum.map_join([b("e", "epic"), b("excluded", "epic")], "\n", &Jason.encode!/1)
    )

    {:ok, filtered, _} = live(conn, "/?q=Title+excluded")
    assert has_element?(filtered, "#epics [data-bead=excluded]")
    refute has_element?(filtered, "#epics [data-bead=e]")
  end

  test "curated views default to Open and selection patches while retaining search and project",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#view-open[aria-pressed=true][type=button]")
    assert has_element?(view, "#initiative-filters[phx-submit=filter]")
    assert has_element?(view, "#view-in-flight")
    assert has_element?(view, "#view-stale")
    assert has_element?(view, "#view-all")
    render_patch(view, "/?view=open&project=sample&q=Title")
    assert_patch(view)
    view |> element("#view-in-flight") |> render_click()
    params = URI.decode_query(URI.parse(assert_patch(view)).query)
    assert params["view"] == "in-flight"
    assert params["project"] == "sample"
    assert params["q"] == "Title"
    refute has_element?(view, "[data-bead=e]")
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "worker"}})
    send(view.pid, :reconcile)
    assert has_element?(view, "[data-bead=e]")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "[data-bead=f]")
    refute has_element?(view, "[data-bead=a]")
    view |> element("#view-all") |> render_click()
    assert has_element?(view, "[data-bead=a]")
  end

  test "Filters starts closed, counts only advanced overrides and remembers disclosure independently",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/?view=open&type=bug&label=follow-up&q=Title&project=sample")
    assert has_element?(view, "#toggle-filters[aria-expanded=false]")
    assert has_element?(view, "#advanced-filters[hidden]")
    assert has_element?(view, "#advanced-filter-count", "2")
    refute has_element?(view, "#filters_project")
    view |> element("#toggle-filters") |> render_click()
    assert has_element?(view, "#toggle-filters[aria-expanded=true]")
    refute has_element?(view, "#advanced-filters[hidden]")
    refute has_element?(view, "#advanced-filter-count")
    assert has_element?(view, "#initiative-filter-memory[data-filters-open=true]")
    view |> element("#view-stale") |> render_click()
    assert has_element?(view, "#toggle-filters[aria-expanded=true]")

    {:ok, returned, _} =
      live(put_connect_params(conn, %{"initiative_filters_open" => "true"}), "/?view=all")

    assert has_element?(returned, "#toggle-filters[aria-expanded=true]")
    {:ok, corrupt, _} = live(put_connect_params(conn, %{"initiative_filters_open" => "bad"}), "/")
    assert has_element?(corrupt, "#toggle-filters[aria-expanded=false]")
    refute has_element?(corrupt, "#advanced-filter-count")
  end

  test "legacy URLs remain unscoped and explicit overrides beat a view", %{conn: conn} do
    rows = Foreman.Beads.Projection.list_raw("sample") ++ [b("closed", "epic", [], "closed")]
    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    {:ok, legacy, _} = live(conn, "/?status=closed")
    refute has_element?(legacy, "#initiative-views [aria-pressed=true]")
    assert has_element?(legacy, "#done-count", "1")
    {:ok, explicit, _} = live(conn, "/?view=open&status=closed")
    assert has_element?(explicit, "#done-count", "1")
    assert has_element?(explicit, "#advanced-filter-count", "1")
    {:ok, all, _} = live(conn, "/?view=open&status=all")
    assert has_element?(all, "#done-count", "1")
    {:ok, unknown, _} = live(conn, "/?view=missing")
    assert has_element?(unknown, "#view-open[aria-pressed=true]")
    assert has_element?(unknown, "#done-count", "0")
  end

  test "reload updates curated buttons and resolves a removed selection to the new default", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/?view=in-flight")
    config = Foreman.RuntimeState.config().config
    config = Map.put(config, "views", [%{"key" => "everything", "title" => "Everything"}])
    Foreman.Repo.query!("UPDATE board_config SET config = $1 WHERE id = 1", [config])
    send(view.pid, :reconcile)
    assert has_element?(view, "#view-everything[aria-pressed=true]", "Everything")
    refute has_element?(view, "#view-in-flight")
    assert has_element?(view, "[data-bead=e]")
  end

  test "persisted pre-views configuration uses shipped presets until its next reload", %{
    conn: conn
  } do
    config = Map.delete(Foreman.RuntimeState.config().config, "views")
    Foreman.Repo.query!("UPDATE board_config SET config = $1 WHERE id = 1", [config])
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#view-open[aria-pressed=true]")
  end

  test "advanced count includes a false-valued label and disabling the stale preset", %{
    conn: conn
  } do
    rows =
      Foreman.Beads.Projection.list_raw("sample") ++
        [Map.put(b("flag", "task"), :labels, ["false"])]

    Foreman.Beads.Projection.replace("sample", Enum.map_join(rows, "\n", &Jason.encode!/1))
    {:ok, view, _} = live(conn, "/?view=stale&label=false&stale=false")
    assert has_element?(view, "#advanced-filter-count", "2")
    render_patch(view, "/?view=all&status=all&stale=false")
    refute has_element?(view, "#advanced-filter-count")
  end

  test "Stale selects stale tickets without changing rollups or counting the preset as advanced",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/?view=stale")
    refute has_element?(view, "[data-bead=e]")
    refute has_element?(view, "#advanced-filter-count")
    Foreman.Overlay.apply_event({"sample", "f"}, {:dispatch, %{window: "worker"}})
    Foreman.Repo.query!("UPDATE sessions SET last_seen_at = NOW() - INTERVAL '3 hours'")
    send(view.pid, :reconcile)
    assert has_element?(view, "[data-bead=e] [aria-valuemax='2']")
    view |> element("[data-bead=e] button") |> render_click()
    assert has_element?(view, "[data-bead=f]")
    refute has_element?(view, "[data-bead=a]")
    refute has_element?(view, "#advanced-filter-count")
  end

  defp ids(view, selector),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("data-bead")

  defp b(id, type, edges \\ [], status \\ "open"),
    do: %{id: id, title: "Title #{id}", issue_type: type, status: status, dependencies: edges}
end
