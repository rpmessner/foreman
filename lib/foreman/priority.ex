defmodule Foreman.Priority do
  @moduledoc "Effective ticket priority and the executor for PriorityOverride. Ticket files remain read-only."
  import Ecto.Query
  alias Foreman.{Repo, PriorityOverride}

  def rank(value) when is_integer(value) and value in 0..4, do: value
  def rank(_), do: 5
  def levels, do: Enum.to_list(0..4)
  @doc "Hydrate and order keyed read models; ties retain their existing order."
  def sort(items) do
    values = for_keys(Enum.map(items, & &1.key))
    jumps = pending_jumps() |> Enum.with_index() |> Map.new(fn {j, i} -> {{j.repo, j.id}, i} end)

    items
    |> Enum.map(fn item ->
      Map.merge(
        item,
        Map.get(values, item.key, %{priority: nil, file: nil, changed_on_board: false})
      )
      |> Map.put(:jump_order, jumps[item.key])
    end)
    |> Enum.sort_by(&order_key/1)
  end

  def order_key(item) do
    jump = Map.get(item, :jump_order)
    {rank(Map.get(item, :priority)), if(is_nil(jump), do: 1, else: 0), jump || 0}
  end

  @doc "Promote a queued ticket to P0 and record its queue jump atomically."
  def jump({repo, _} = key, actor) do
    Repo.transaction(fn ->
      lock(repo)

      case Foreman.Overlay.get(key) do
        %{machine: Foreman.Stage, stage: :queued} ->
          with {:ok, 0} <- put(key, 0, actor),
               {:ok, _} <-
                 Foreman.Overlay.apply_event(key, {:jump, %{priority: 0}}, %{actor: actor}) do
            0
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          Repo.rollback(:not_found)

        _ ->
          Repo.rollback(:not_queued)
      end
    end)
  end

  @doc "Latest jump per queued ticket, excluding jumps consumed by a prior dispatch."
  def pending_jumps do
    latest =
      from e in "stage_events",
        where: e.event == "jump" and e.outcome == "row",
        group_by: [e.repo_key, e.bead_id],
        select: %{repo: e.repo_key, bead: e.bead_id, id: max(e.id)}

    departed =
      from e in "stage_events",
        where: e.outcome == "row" and e.to_stage != "queued",
        group_by: [e.repo_key, e.bead_id],
        select: %{repo: e.repo_key, bead: e.bead_id, id: max(e.id)}

    Repo.all(
      from l in subquery(latest),
        join: e in "stage_events",
        on: e.id == l.id,
        join: t in "tickets",
        on: t.repo_key == l.repo and t.bead_id == l.bead,
        join: b in "beads",
        on: b.repo_key == l.repo and b.bead_id == l.bead,
        left_join: d in subquery(departed),
        on: d.repo == l.repo and d.bead == l.bead,
        where: t.stage == "queued" and (is_nil(d.id) or d.id < l.id),
        order_by: [desc: e.id],
        select: %{repo: e.repo_key, id: e.bead_id, actor: e.actor, at: e.inserted_at}
    )
    |> Enum.map(&%{&1 | at: DateTime.from_naive!(&1.at, "Etc/UTC")})
  end

  def for_keys([]), do: %{}

  def for_keys(keys) do
    repos = Enum.uniq_by(keys, &elem(&1, 0)) |> Enum.map(&elem(&1, 0))
    ids = Enum.map(keys, &elem(&1, 1)) |> Enum.uniq()
    wanted = MapSet.new(keys)
    overrides = override_map(repos)

    Repo.all(
      from b in "beads",
        where: b.repo_key in ^repos and b.bead_id in ^ids,
        select: {{b.repo_key, b.bead_id}, fragment("?->'priority'", b.raw)}
    )
    |> Enum.filter(fn {key, _} -> MapSet.member?(wanted, key) end)
    |> Map.new(fn {key, file} ->
      value = overrides[key]

      {key,
       %{
         priority: if(is_nil(value), do: file, else: value),
         file: file,
         changed_on_board: not is_nil(value)
       }}
    end)
  end

  def override_map(repos) do
    Repo.all(
      from o in "priority_overrides",
        where: o.repo_key in ^repos,
        select: {{o.repo_key, o.bead_id}, o.priority}
    )
    |> Map.new()
  end

  def overrides do
    Repo.all(
      from o in "priority_overrides",
        join: b in "beads",
        on: b.repo_key == o.repo_key and b.bead_id == o.bead_id,
        order_by: [desc: o.updated_at, desc: o.id],
        select: %{
          repo: o.repo_key,
          id: o.bead_id,
          priority: o.priority,
          file_priority: fragment("?->'priority'", b.raw),
          actor: o.actor,
          at: o.updated_at
        }
    )
  end

  def set({repo, _} = key, value, actor) do
    Repo.transaction(fn ->
      lock(repo)

      case put(key, value, actor) do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Reconcile the committed projection under the same repository lock as board edits."
  def reconcile(repo) do
    {:ok, :ok} = Repo.transaction(fn -> reconcile_locked(repo) end)
    :ok
  end

  defp reconcile_locked(repo) do
    lock(repo)

    rows =
      Repo.all(
        from o in "priority_overrides",
          join: b in "beads",
          on: b.repo_key == o.repo_key and b.bead_id == o.bead_id,
          where: o.repo_key == ^repo,
          select: {o.bead_id, o.priority, fragment("?->'priority'", b.raw)}
      )

    Enum.each(rows, fn {id, value, file} ->
      {_, effects} = PriorityOverride.step(:board, {:synced, %{priority: value, file: file}}, nil)
      interpret(effects, {repo, id}, value, "sync")
    end)

    :ok
  end

  defp put(_, value, _) when not (is_integer(value) and value in 0..4),
    do: {:error, :invalid_priority}

  defp put(key, value, actor) do
    case for_keys([key])[key] do
      nil ->
        {:error, :not_found}

      current ->
        state = if current.changed_on_board, do: :board, else: :file

        {_, effects} =
          PriorityOverride.step(state, {:set, %{priority: value, file: current.file}}, nil)

        interpret(effects, key, value, actor)
        {:ok, value}
    end
  end

  defp interpret(effects, {repo, id}, value, actor) do
    Enum.each(effects, fn
      {:store, :override} ->
        now = DateTime.utc_now()

        Repo.insert_all(
          "priority_overrides",
          [
            %{
              repo_key: repo,
              bead_id: id,
              priority: value,
              actor: actor,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:priority, :actor, :updated_at]},
          conflict_target: [:repo_key, :bead_id]
        )

      {:clear, :override} ->
        Repo.delete_all(
          from o in "priority_overrides", where: o.repo_key == ^repo and o.bead_id == ^id
        )
    end)

    if effects != [], do: Foreman.Events.broadcast(:overlay_changed, repo <> "/" <> id)
  end

  defp lock(repo),
    do:
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "foreman:overlay:" <> repo
      ])
end
