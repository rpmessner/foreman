defmodule ForemanWeb.PriorityBadge do
  use ForemanWeb, :html
  alias Fluxon.Components.Badge

  attr :priority, :any, required: true

  def badge(assigns) do
    ~H"""
    <span :if={Foreman.Priority.rank(@priority) < 5} data-priority={@priority} class="shrink-0">
      <Badge.badge color={color(@priority)}>P{@priority}</Badge.badge>
    </span>
    """
  end

  defp color(0), do: "danger"
  defp color(1), do: "warning"
  defp color(_), do: "neutral"
end
