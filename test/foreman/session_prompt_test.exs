defmodule Foreman.SessionPromptTest do
  use ExUnit.Case, async: true

  test "each ticket kind starts its workflow and identifies the ticket" do
    for {kind, workflow} <- [
          {"epic", "/tight-spec"},
          {"bug", "diagnosing-bugs"},
          {"feature", "flow"},
          {"task", "flow"},
          {"decision", "flow"},
          {"chore", "flow"}
        ] do
      text =
        Foreman.SessionPrompt.render(
          kind,
          %{ticket: "x-1", source: "tickets/x-1.md", project: "sample"},
          directory: "/nonexistent"
        )

      assert text =~ workflow
      assert text =~ "tickets/x-1.md"
      assert text =~ "x-1"
    end
  end

  test "ticketed epic prompt owns only its epic and dispatches panes without planning again" do
    text =
      Foreman.SessionPrompt.render(
        "epic",
        %{
          ticket: "x-2",
          project: "sample",
          source: "tickets/x-2.md",
          stage: :ticketed
        },
        directory: "/nonexistent",
        fallback: false
      )

    assert is_binary(text)
    assert text =~ "x-2"
    assert text =~ "tickets/x-2.md"
    assert text =~ "dispatch"
    assert text =~ "pi-window --pane"
    assert text =~ "own window"
    assert text =~ "ready"
    assert text =~ "reported"
    assert text =~ "requests"
    assert text =~ "only when"
    refute text =~ "/tight-spec"
  end

  test "missing skill templates are refused outside the test fallback" do
    assert Foreman.SessionPrompt.render(
             "task",
             %{ticket: "x-1", source: "tickets/x-1.md", project: "sample"},
             directory: "/nonexistent",
             fallback: false
           ) == {:error, :prompt_unavailable}
  end

  test "skill-owned template overrides the built-in fallback" do
    dir = Path.join(System.tmp_dir!(), "fm-prompts-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "bug.md"), "diagnosing-bugs {{ticket}} in {{project}}: {{source}}")

    assert Foreman.SessionPrompt.render(
             "bug",
             %{ticket: "x-2", source: "tickets/x-2.md", project: "sample"},
             directory: dir
           ) ==
             "diagnosing-bugs x-2 in sample: tickets/x-2.md"
  end
end
