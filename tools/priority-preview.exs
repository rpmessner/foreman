Logger.configure(level: :warning)
database = System.fetch_env!("PRIORITY_PREVIEW_DATABASE")
unless String.starts_with?(database, "foreman_preview_fm_priority_"), do: raise("not this preview")
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
config = Application.fetch_env!(:foreman, Foreman.Repo)
Application.put_env(:foreman, Foreman.Repo, Keyword.merge(config, database: database, pool: DBConnection.ConnectionPool))
{:ok, _} = Foreman.Repo.start_link()
Application.ensure_all_started(:oban)
{:ok, _} = Oban.start_link(Application.fetch_env!(:foreman, Oban))
alias Foreman.{Repo, Priority}

case System.argv() do
  ["seed"] ->
    Repo.delete_all("request_events")
    Repo.delete_all(Foreman.Requests.Request)
    {:ok, config} = Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])
    config = Map.put(config, "repos", [%{"key" => "priority-demo", "path" => "/tmp/priority-demo", "enabled" => true, "tickets" => "files"}])
    Repo.insert_all("board_config", [%{id: 1, config: config, source: "preview", discovered: [], loaded_at: DateTime.utc_now()}], on_conflict: {:replace, [:config]}, conflict_target: [:id])
    rows = [
      %{id: "demo-epic", issue_type: "epic", priority: 2, title: "Board priorities"},
      %{id: "demo-a", priority: 4, title: "Add keyboard shortcuts", dependencies: [%{depends_on_id: "demo-epic", type: "parent-child"}]},
      %{id: "demo-b", priority: 0, title: "Repair stalled builds", dependencies: [%{depends_on_id: "demo-epic", type: "parent-child"}]},
      %{id: "demo-c", priority: 2, title: "Improve ticket search", dependencies: [%{depends_on_id: "demo-epic", type: "parent-child"}]}
    ] |> Enum.map(&Map.merge(%{title: "Demo ticket", issue_type: "task", status: "open", created_at: "2026-10-20T10:00:00Z", dependencies: []}, &1))
    Foreman.Beads.Projection.replace("priority-demo", Enum.map_join(rows, "\n", &Jason.encode!/1))
    requests = for id <- ~w(demo-a demo-b demo-c) do
      Repo.insert!(%Foreman.Requests.Request{repo_key: "priority-demo", bead_id: id, kind: "decision", actor: "pi", session: "preview-build", state: "pending", facts: %{"question" => "Which layout should this ticket use?", "options" => ["Wide", "Compact"]}})
    end
    IO.puts(Jason.encode!(%{requests: Map.new(requests, &{&1.bead_id, &1.id})}))
  ["reset"] ->
    Priority.set({"priority-demo", "demo-a"}, 4, "preview")
    IO.puts("reset")
  ["overlay"] ->
    {200, body} = Foreman.AgentCommands.execute(%{"action" => "ls", "project" => "priority-demo"})
    IO.puts(Jason.encode!(body))
  ["sync"] ->
    rows = Foreman.Beads.Projection.list_raw("priority-demo") |> Enum.map(fn row -> if row["id"] == "demo-a", do: Map.put(row, "priority", 0), else: row end)
    Foreman.Beads.Projection.replace("priority-demo", Enum.map_join(rows, "\n", &Jason.encode!/1))
    IO.puts(Jason.encode!(%{overrides: Priority.overrides()}))
end
