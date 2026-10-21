Logger.configure(level: :warning)
database = System.fetch_env!("ORPHANS_PREVIEW_DATABASE")
unless String.starts_with?(database, "foreman_preview_fm_orphans_"), do: raise("not this preview")
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
alias Foreman.{Requests, Overlay}
ticket = System.fetch_env!("ORPHANS_PREVIEW_TICKET")
key = {"orphans-preview", ticket}

case System.argv() do
  ["ask"] ->
    Overlay.backfill("orphans-preview", [
      %{bead_id: ticket, issue_type: "task", status: "open"}
    ])

    for request <- Requests.pending(), request.repo_key == "orphans-preview" do
      Requests.resolve(request.id, :withdraw, %{})
    end

    case Overlay.get(key).stage do
      :queued ->
        Overlay.apply_event(key, {:dispatch, %{window: "fm-orphans-preview"}})

      :reported ->
        Overlay.apply_event(
          key,
          {:progress, %{window: "fm-orphans-preview", body: "Preview rerun"}}
        )

      _ ->
        :ok
    end

    {:ok, request} =
      Requests.ask(key, "decision", %{
        "actor" => "pi",
        "session" => "fm-orphans-preview",
        "facts" => %{
          "question" => "Which layout should the build use?",
          "options" => ["Wide", "Compact"]
        }
      })

    IO.puts(Jason.encode!(%{id: request.id}))

  ["timeout", id] ->
    {:ok, request} = Requests.wait(id, 0)
    IO.puts(Jason.encode!(request))

  ["report"] ->
    {:ok, _} =
      Overlay.apply_event(
        key,
        {:report, %{window: "fm-orphans-preview", path: "docs/sessions/fm-orphans.md"}}
      )

    IO.puts("reported")

  ["wait", id] ->
    {:ok, request} = Requests.wait(id, 0)
    IO.puts(Jason.encode!(request))
end
