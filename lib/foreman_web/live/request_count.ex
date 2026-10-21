defmodule ForemanWeb.RequestCount do
  @moduledoc "Shared authoritative inbox count; mount, notifications and periodic reconciliation."
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _, _, socket) do
    if connected?(socket) do
      Foreman.Events.subscribe()
      Process.send_after(self(), :request_count_tick, 3_000)
    end

    {:cont,
     socket
     |> ForemanWeb.RequestDrawer.mount()
     |> refresh()
     |> attach_hook(:request_count_params, :handle_params, fn _, _, socket ->
       {:cont, refresh(socket)}
     end)
     |> attach_hook(:request_count, :handle_info, &handle_info/2)
     |> attach_hook(:notification_sync, :handle_event, fn
       "notification_sync", _, socket ->
         {:halt, %{requests: notification_requests(Foreman.Requests.pending())}, socket}

       _, _, socket ->
         {:cont, socket}
     end)}
  end

  def refresh(socket) do
    pending = Foreman.Requests.pending()
    count = length(pending) + length(Foreman.Requests.not_picked_up())

    socket
    |> assign(
      pending_count: count,
      page_title: if(count > 0, do: "(#{count}) foreman", else: "foreman")
    )
    |> push_event("notification_snapshot", %{requests: notification_requests(pending)})
    |> ForemanWeb.RequestDrawer.refresh(pending)
  end

  defp notification_requests(pending) do
    Enum.map(pending, fn request ->
      %{id: request.id, kind: request.kind, ticket: request.bead_id}
    end) ++
      Enum.map(Foreman.Requests.not_picked_up(), fn request ->
        {title, body} = Foreman.OsNotifications.message(request)

        %{
          id: request.id <> ":answer",
          kind: request.kind,
          ticket: request.bead_id,
          title: title,
          body: body
        }
      end)
  end

  defp handle_info(:request_count_tick, socket) do
    Process.send_after(self(), :request_count_tick, 3_000)
    {:halt, refresh(socket)}
  end

  defp handle_info({:notification, :foreman_events, _}, socket), do: {:cont, refresh(socket)}
  defp handle_info(_, socket), do: {:cont, socket}
end
