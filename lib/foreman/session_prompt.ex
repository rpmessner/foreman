defmodule Foreman.SessionPrompt do
  @moduledoc "Renders the epic execution prompt and loads skill-owned planning templates from templates/session-launch. Planning fallback is enabled only by test configuration."
  @workflows %{
    "epic" => "/tight-spec",
    "bug" => "diagnosing-bugs",
    "feature" => "flow",
    "task" => "flow"
  }

  def render(kind, context, opts \\ [])

  def render("epic", %{stage: stage} = context, _opts)
      when stage in [:ticketed, :building, :shipping, :shipped] do
    """
    You are the epic coordinator for #{context.ticket} in project #{context.project}.
    Read AGENTS.md and #{context.source}. Own only this epic: orient on its ready, in-flight and reported tickets and open requests, not other epics.
    Use the dispatch skill for its ready frontier, in pane mode (pi-window --pane): builds belong in your own window in this project's tmux session, inheriting this tmux server.
    Follow dispatch and foreman for review and close-out; commit only when the user asks, and use board requests for push/PR/merge.
    """
  end

  def render(kind, context, opts) do
    kind = if Map.has_key?(@workflows, kind), do: kind, else: "task"
    workflow = Map.fetch!(@workflows, kind)

    directory =
      Keyword.get(
        opts,
        :directory,
        Path.expand("~/.agents/skills/foreman/templates/session-launch")
      )

    fallback = """
    You are the coordinator for {{ticket}} in project {{project}}.
    Read AGENTS.md and {{source}}. Start #{workflow} for this ticket.
    Keep planning scoped to this ticket. Follow the foreman skill for board updates and the house workflow for specs, build dispatch, and review. Ask the user when a decision is theirs.
    """

    template =
      case File.read(Path.join(directory, kind <> ".md")) do
        {:ok, text} ->
          text

        _ ->
          if Keyword.get(
               opts,
               :fallback,
               Application.get_env(:foreman, :session_prompt_fallback, false)
             ), do: fallback, else: {:error, :prompt_unavailable}
      end

    if is_binary(template) do
      Regex.replace(~r/\{\{(ticket|project|source)\}\}/, template, fn _, name ->
        Map.fetch!(
          context,
          %{"ticket" => :ticket, "project" => :project, "source" => :source}[name]
        )
      end)
    else
      template
    end
  end
end
