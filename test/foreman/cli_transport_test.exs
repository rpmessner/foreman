defmodule Foreman.CLITransportTest do
  use Foreman.DataCase, async: false
  import ExUnit.CaptureIO
  alias Foreman.{CLI, Repo, Overlay}

  setup_all do
    Mix.Task.run("escript.build", ["--no-compile"])
    :ok
  end

  setup do
    path = Path.join(System.tmp_dir!(), "cli-token-#{System.unique_integer([:positive])}")
    File.write!(path, "test-only-token-long")
    old = Application.get_env(:foreman, :token_file)
    Application.put_env(:foreman, :token_file, path)

    on_exit(fn ->
      File.rm!(path)

      if old,
        do: Application.put_env(:foreman, :token_file, old),
        else: Application.delete_env(:foreman, :token_file)
    end)

    :ok
  end

  test "every CLI write verb reaches the API, including drafts and cross-repo links" do
    # Run outside any checkout: this repo now has tickets/, which would route ticket verbs to files.
    outside = Path.join(System.tmp_dir!(), "cli-outside-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    {:ok, config} =
      Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

    config =
      Map.put(config, "repos", [
        %{"key" => "sample", "path" => "/tmp/sample", "enabled" => true},
        %{"key" => "other", "path" => "/tmp/other", "enabled" => true}
      ])

    Repo.insert_all("board_config", [
      %{id: 1, config: config, source: "test", discovered: [], loaded_at: DateTime.utc_now()}
    ])

    Foreman.Beads.Projection.replace(
      "sample",
      Enum.map_join(
        [
          %{id: "s-1", title: "Ticket", issue_type: "task", status: "open"},
          %{id: "s-e", title: "Epic", issue_type: "epic", status: "open"}
        ],
        "\n",
        &Jason.encode!/1
      )
    )

    Foreman.Beads.Projection.replace(
      "other",
      Jason.encode!(%{id: "o-e", title: "Other epic", issue_type: "epic", status: "open"})
    )

    Req.Test.stub(__MODULE__, fn conn -> ForemanWeb.Endpoint.call(conn, []) end)

    for {args, stage} <- [
          {["dispatch", "s-1", "--session", "build"], "dispatched"},
          {["progress", "s-1", "working"], "building"},
          {["report", "s-1", "--path", "report.md"], "reported"},
          {["review", "s-1"], "in_review"},
          {["changes", "s-1", "fix it"], "building"},
          {["report", "s-1"], "reported"},
          {["review", "s-1"], "in_review"},
          {["commit", "s-1", "--sha", "abc"], "committed"},
          {["abandon", "s-1"], "abandoned"},
          {["revive", "s-1"], "queued"},
          {["epic", "create", "idea", "--title", "Idea", "--project", "sample"], "idea"},
          {["epic", "spec", "idea", "--project", "sample"], "speccing"},
          {["epic", "approve", "idea", "--spec", "spec.md", "--project", "sample"],
           "spec_approved"},
          {["epic", "abandon", "idea", "--project", "sample"], "abandoned"},
          {["epic", "revive", "idea", "--project", "sample"], "idea"},
          {["epic", "spec", "idea", "--project", "sample"], "speccing"},
          {["epic", "approve", "idea", "--project", "sample"], "spec_approved"},
          {["epic", "ticket", "idea", "--beads-epic-id", "s-e", "--project", "sample"],
           "ticketed"},
          {["attach", "s-1", "--epic", "o-e"], "queued"},
          {["detach", "s-1", "--epic", "o-e"], "queued"},
          {["show", "s-1"], "queued"}
        ] do
      output =
        capture_io(fn ->
          assert CLI.run(args ++ ["--json"],
                   req_options: [plug: {Req.Test, __MODULE__}],
                   cwd: outside
                 ) == 0
        end)

      assert Jason.decode!(output)["stage"] == stage, inspect(args) <> ": " <> output
    end

    output =
      capture_io(fn ->
        assert CLI.run(["ls", "--stage", "queued", "--json"],
                 req_options: [plug: {Req.Test, __MODULE__}]
               ) == 0
      end)

    assert Jason.decode!(output)["items"] == [
             %{"repo" => "sample", "id" => "s-1", "stage" => "queued"}
           ]
  end

  test "ls --overlay retains items and adds priority overrides and jumps" do
    Foreman.Beads.Projection.replace(
      "sample",
      Jason.encode!(%{
        id: "s-1",
        title: "Ticket",
        issue_type: "task",
        status: "open",
        priority: 3
      })
    )

    assert {:ok, 0} = Foreman.Priority.jump({"sample", "s-1"}, "user")
    Req.Test.stub(__MODULE__, fn conn -> ForemanWeb.Endpoint.call(conn, []) end)

    output =
      capture_io(fn ->
        assert CLI.run(["ls", "--overlay", "--project", "sample", "--json"],
                 req_options: [plug: {Req.Test, __MODULE__}]
               ) == 0
      end)

    body = Jason.decode!(output)
    assert body["items"] == [%{"repo" => "sample", "id" => "s-1", "stage" => "queued"}]

    assert [%{"id" => "s-1", "priority" => 0, "file_priority" => 3, "actor" => "user"}] =
             body["priority_overrides"]

    assert [%{"repo" => "sample", "id" => "s-1", "actor" => "user"}] = body["jumps"]
  end

  test "JSON mode also covers malformed CLI input" do
    output = capture_io(fn -> assert CLI.run(["review", "s-1", "--typo", "--json"]) == 0 end)
    assert Jason.decode!(output)["warning"] =~ "usage"
  end

  test "JSON output and exit 3 preserve the API's stage and allowed events" do
    Overlay.backfill("sample", [%{bead_id: "s-1", status: "open", issue_type: "task"}])

    Foreman.Beads.Projection.replace(
      "sample",
      Jason.encode!(%{id: "s-1", title: "Test", status: "open", issue_type: "task"})
    )

    Req.Test.stub(__MODULE__, fn conn -> ForemanWeb.Endpoint.call(conn, []) end)
    # Explicit project avoids requiring a global config fixture for this HTTP contract.
    request = %{
      "repo" => "sample",
      "id" => "s-1",
      "action" => "event",
      "event" => "review",
      "request_id" => Ecto.UUID.generate()
    }

    assert {3, %{"stage" => "queued", "allowed" => allowed}} =
             Foreman.CLITransport.deliver(request, req_options: [plug: {Req.Test, __MODULE__}])

    assert "dispatch" in allowed

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn |> Plug.Conn.put_status(409), %{
        stage: "queued",
        allowed: ["dispatch", "abandon"]
      })
    end)

    output =
      capture_io(fn ->
        assert CLI.run(["review", "s-1", "--json"], req_options: [plug: {Req.Test, __MODULE__}]) ==
                 3
      end)

    assert Jason.decode!(output) == %{"stage" => "queued", "allowed" => ["dispatch", "abandon"]}
  end

  test "app unavailable writes directly to Postgres and still exits zero" do
    id = isolated_spool_id()

    request = %{
      "request_id" => Ecto.UUID.generate(),
      "action" => "event",
      "event" => "progress",
      "id" => id
    }

    db = Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])

    assert {0, %{"warning" => "foreman unavailable; event spooled for replay"}} =
             Foreman.CLITransport.deliver(request, url: "http://127.0.0.1:1", database: db)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      uuid = Ecto.UUID.dump!(request["request_id"])

      assert Repo.one(from s in "spooled_events", where: s.request_id == ^uuid, select: s.request) ==
               request
    end)
  end

  test "built escript uses PG settings when database URL variables are empty" do
    id = isolated_spool_id()

    {output, status} =
      System.cmd(Path.expand("foreman"), ["progress", id, "offline", "--json"],
        env: [
          {"FOREMAN_URL", "http://127.0.0.1:1"},
          {"FOREMAN_TOKEN_FILE", "/does-not-exist"},
          {"PGHOST", "127.0.0.1"},
          {"PGPORT", "5432"},
          {"PGUSER", "postgres"},
          {"PGPASSWORD", "postgres"},
          {"PGDATABASE", Repo.config()[:database]},
          {"FOREMAN_DATABASE_URL", ""},
          {"DATABASE_URL", ""}
        ],
        stderr_to_stdout: true
      )

    assert status == 0
    body = Jason.decode!(output)
    assert body["warning"] =~ "event spooled"
    uuid = Ecto.UUID.dump!(body["request_id"])

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      assert Repo.one(from s in "spooled_events", where: s.request_id == ^uuid, select: s.state) ==
               "pending"
    end)
  end

  defp isolated_spool_id do
    id = "cli-spool-#{Ecto.UUID.generate()}"

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from s in "spooled_events", where: fragment("?->>'id'", s.request) == ^id)
      end)
    end)

    id
  end

  test "built escript survives a failed linked Postgres connection" do
    {output, status} =
      System.cmd(Path.expand("foreman"), ["progress", "s-1", "offline", "--json"],
        env: [
          {"FOREMAN_URL", "http://127.0.0.1:1"},
          {"FOREMAN_TOKEN_FILE", "/does-not-exist"},
          {"PGHOST", "127.0.0.1"},
          {"PGPORT", "1"},
          {"FOREMAN_DATABASE_URL", nil},
          {"DATABASE_URL", nil}
        ],
        stderr_to_stdout: true
      )

    assert status == 0
    assert Jason.decode!(output)["warning"] =~ "event not saved"
  end

  @tag capture_log: true
  test "Postgres unavailable too is a warning, exit zero, bounded wait" do
    output =
      capture_io(fn ->
        assert CLI.run(["progress", "s-1", "working", "--json"],
                 url: "http://127.0.0.1:1",
                 database: [hostname: "127.0.0.1", port: 1, username: "none", database: "none"]
               ) == 0
      end)

    assert Jason.decode!(output)["warning"] =~ "event not saved"
  end

  @tag capture_log: true
  test "missing token spools without making an HTTP request" do
    Application.put_env(:foreman, :token_file, "/does-not-exist")

    output =
      capture_io(fn ->
        assert CLI.run(["review", "s-1", "--json"],
                 database: [hostname: "127.0.0.1", port: 1, username: "none", database: "none"]
               ) == 0
      end)

    assert Jason.decode!(output)["warning"] =~ "event not saved"
  end

  test "a session_waiting ask is never spooled when foreman is unavailable" do
    outside = Path.join(System.tmp_dir!(), "cli-outside-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)
    db = Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])
    ticket = isolated_spool_id()

    count = fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.one(
          from s in "spooled_events",
            where: fragment("?->>'id' = ?", s.request, ^ticket),
            select: count()
        )
      end)
    end

    capture_io(fn ->
      assert CLI.run(
               [
                 "ask",
                 "session_waiting",
                 ticket,
                 "--reason",
                 "input",
                 "--session",
                 "s-1",
                 "--json"
               ],
               url: "http://127.0.0.1:1",
               database: db,
               cwd: outside
             ) == 0
    end)

    assert count.() == 0
  end
end
