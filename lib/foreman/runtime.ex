defmodule Foreman.Runtime do
  @moduledoc "Worker-only nominal scheduler. Schedule owns admission; Oban owns job lifecycle."
  use GenServer
  alias Foreman.Beads.{Schedule, SyncJob}
  import Ecto.Query

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def ping(key), do: Foreman.Events.broadcast(:sync_requested, key)

  @impl true
  def init(_) do
    {:ok, _} =
      DynamicSupervisor.start_link(strategy: :one_for_one, name: Foreman.TicketFiles.Supervisor)

    Foreman.Events.subscribe()
    Foreman.Config.ReloadJob.enqueue()
    send(self(), :tick)
    Process.send_after(self(), :sweep, 300_000)
    {:ok, %{epoch: Ecto.UUID.generate(), schedules: %{}, jobs: %{}, readers: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, 3_000)
    {:noreply, reconcile(state)}
  end

  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, 300_000)
    {:noreply, reconcile(state)}
  end

  def handle_info(
        {:notification, :foreman_events, %{"kind" => "sync_requested", "key" => key}},
        state
      ),
      do: {:noreply, reconcile(state, key)}

  def handle_info(
        {:notification, :foreman_events, %{"kind" => "forge_requested", "key" => key}},
        state
      ) do
    if Foreman.Forge.SyncJob.configured(key) &&
         Foreman.Forge.SyncJob.due?(Foreman.Forge.Store.get(key), true),
       do: Foreman.Forge.SyncJob.enqueue(key, true)

    {:noreply, state}
  end

  def handle_info({:notification, :foreman_events, %{"kind" => "config_changed"}}, state),
    do: {:noreply, reconcile(state)}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    readers = Map.reject(state.readers, fn {_, {_, reader}} -> reader == pid end)
    {:noreply, reconcile(%{state | readers: readers})}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp reconcile(state, requested \\ :all) do
    Foreman.Requests.reconcile_pickups()
    Foreman.Requests.reconcile_pushes()
    Foreman.Requests.reconcile_open_prs()
    Foreman.Requests.reconcile_merges()
    now = System.monotonic_time(:millisecond)
    config = Foreman.RuntimeState.config()
    repos = (config && config.config["repos"]) || []

    Enum.each(repos, fn repo ->
      if repo["enabled"] && repo["forge"] == "github" && repo["github"] &&
           Foreman.Forge.SyncJob.due?(Foreman.Forge.Store.get(repo["key"])) do
        Foreman.Forge.SyncJob.enqueue(repo["key"])
      end
    end)

    state = reconcile_readers(state, repos, requested)

    groups =
      repos
      |> Enum.filter(&(&1["enabled"] and &1["tickets"] != "files"))
      |> Enum.group_by(
        fn repo ->
          get_in(config.stores, [repo["key"], "identity"]) || repo["key"]
        end,
        & &1["key"]
      )

    enabled = MapSet.new(Map.keys(groups))
    keys = MapSet.union(enabled, MapSet.new(Map.keys(state.schedules)))

    Enum.reduce(keys, state, fn key, state ->
      schedule = Map.get(state.schedules, key, Schedule.new(key, state.epoch, now))
      {schedule, state} = finish_terminal(schedule, key, state)

      {schedule, effects} =
        if MapSet.member?(enabled, key),
          do: Schedule.enable(schedule),
          else: Schedule.disable(schedule)

      state = apply_effects(state, effects, groups)

      {schedule, effects} =
        if requested == :all or requested in Map.get(groups, key, []),
          do: Schedule.request(schedule, now),
          else: {schedule, []}

      state = apply_effects(state, effects, groups)
      %{state | schedules: Map.put(state.schedules, key, schedule)}
    end)
  end

  defp reconcile_readers(state, repos, requested) do
    desired =
      repos
      |> Enum.filter(&(&1["enabled"] and &1["tickets"] == "files"))
      |> Map.new(&{&1["key"], &1})

    readers =
      Enum.reduce(state.readers, state.readers, fn {key, {repo, pid}}, readers ->
        if desired[key] != repo do
          DynamicSupervisor.terminate_child(Foreman.TicketFiles.Supervisor, pid)
          Map.delete(readers, key)
        else
          readers
        end
      end)

    readers =
      Enum.reduce(desired, readers, fn {key, repo}, readers ->
        case readers[key] do
          nil ->
            {:ok, pid} =
              DynamicSupervisor.start_child(
                Foreman.TicketFiles.Supervisor,
                {Foreman.TicketFiles.Reader, repo: repo}
              )

            Process.monitor(pid)
            Map.put(readers, key, {repo, pid})

          {_, pid} ->
            if requested == key, do: Foreman.TicketFiles.Reader.rescan(pid)
            readers
        end
      end)

    %{state | readers: readers}
  end

  defp finish_terminal(schedule, key, state) do
    case Map.fetch(state.jobs, key) do
      {:ok, {id, token}} ->
        active =
          Foreman.Repo.exists?(
            from j in Oban.Job,
              where:
                j.id == ^id and
                  j.state in ["available", "scheduled", "executing", "retryable", "suspended"]
          )

        if active do
          {schedule, state}
        else
          {schedule, []} = Schedule.finish(schedule, token)
          {schedule, %{state | jobs: Map.delete(state.jobs, key)}}
        end

      :error ->
        {schedule, state}
    end
  end

  defp apply_effects(state, effects, groups) do
    Enum.reduce(effects, state, fn
      {:enqueue, {key, token}}, state ->
        {:ok, job} = SyncJob.new(%{key: hd(Map.fetch!(groups, key)), store: key}) |> Oban.insert()
        %{state | jobs: Map.put(state.jobs, key, {job.id, token})}

      {:cancel, {key, _token}}, state ->
        case Map.fetch(state.jobs, key) do
          {:ok, {id, _}} -> Oban.cancel_job(id)
          :error -> :ok
        end

        state
    end)
  end
end
