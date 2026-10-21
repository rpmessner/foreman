Logger.configure(level: :warning)
database = System.fetch_env!("HOLD_PREVIEW_DATABASE")
unless String.starts_with?(database, "foreman_preview_fm_parked_"), do: raise("not this preview")
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
config = Application.fetch_env!(:foreman, Foreman.Repo)

Application.put_env(
  :foreman,
  Foreman.Repo,
  Keyword.merge(config, database: database, pool: DBConnection.ConnectionPool)
)

{:ok, _} = Foreman.Repo.start_link()
Application.ensure_all_started(:oban)
{:ok, _} = Oban.start_link(Application.fetch_env!(:foreman, Oban))
alias Foreman.Repo
import Ecto.Query

{:ok, config} =
  Foreman.Config.parse_layers([{"defaults", File.read!("priv/foreman.defaults.toml")}])

config =
  Map.put(config, "repos", [
    %{"key" => "hold-demo", "path" => "/tmp/hold-demo", "enabled" => true, "tickets" => "files"}
  ])

Repo.insert_all(
  "board_config",
  [%{id: 1, config: config, source: "preview", discovered: [], loaded_at: DateTime.utc_now()}],
  on_conflict: {:replace, [:config]},
  conflict_target: [:id]
)

rows =
  [
    %{id: "hold-epic", issue_type: "epic", title: "Improve the build board"},
    %{
      id: "hold-child",
      title: "Add keyboard shortcuts",
      status: "on_hold",
      on_hold_reason: "Waiting for the navigation design review.",
      on_hold_since: "2026-10-20T00:00:00Z",
      dependencies: [%{depends_on_id: "hold-epic", type: "parent-child"}]
    },
    %{
      id: "hold-free",
      title: "Validate the offline workflow",
      status: "on_hold",
      on_hold_reason: "Awaiting a replacement test device.\nResume after the hardware check.",
      on_hold_since: "2026-10-21T00:00:00Z"
    },
    %{id: "hold-next", title: "Improve ticket search"}
  ]
  |> Enum.map(
    &Map.merge(
      %{
        issue_type: "task",
        status: "open",
        priority: 2,
        created_at: "2026-10-19T00:00:00Z",
        dependencies: [],
        acceptance_progress: %{checked: 0, total: 1}
      },
      &1
    )
  )

{:ok, _} =
  Foreman.Beads.Projection.replace("hold-demo", Enum.map_join(rows, "\n", &Jason.encode!/1))

Foreman.Overlay.apply_event(
  {"hold-demo", "hold-free"},
  {:dispatch, %{window: "synthetic-preview"}}
)

Repo.update_all(from(s in "sessions", where: s.repo_key == "hold-demo"),
  set: [last_seen_at: ~N[2020-01-01 00:00:00]]
)

Repo.insert!(
  %Foreman.PlanningSession{
    project: "hold-demo",
    ticket: "hold-free",
    state: :parked,
    workdir: "/tmp/hold-demo",
    launched_at: ~U[2026-10-20 00:00:00.000000Z]
  },
  on_conflict: :nothing,
  conflict_target: [:project, :ticket]
)

IO.puts("seeded")
