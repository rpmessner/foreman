defmodule Foreman.TicketFileTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Foreman.TicketFile

  def canonical(title \\ "A ticket") do
    "---\nid: bb-abc.1\ntitle: #{Jason.encode!(title)}\ntype: task\nstatus: open\npriority: 2\nparent: bb-abc\nblocked_by: []\nrelated: []\nsupersedes: []\ndiscovered_from: null\nlabels: []\ncreated: 2026-10-18\nclosed: null\nclose_reason: null\n---\n\n## Acceptance\n- [ ] Works\n"
  end

  property "canonical parse then print is byte identity, including Unicode and YAML punctuation" do
    check all(
            title <- string(:utf8, min_length: 1),
            priority <- integer(0..4),
            type <- member_of(~w(epic feature task bug decision chore)),
            status <- member_of(~w(open in_progress closed deferred)),
            labels <- list_of(string(:alphanumeric, min_length: 1), max_length: 8),
            prose <- string(:alphanumeric),
            title = "Ticket " <> title
          ) do
      text =
        canonical(title)
        |> String.replace("priority: 2", "priority: #{priority}")
        |> String.replace("type: task", "type: #{type}")
        |> String.replace("status: open", "status: #{status}")
        |> String.replace("labels: []", "labels: #{Jason.encode!(Enum.sort(labels))}")
        |> String.replace("Works", "Works #{prose}")

      assert {:ok, ticket} = TicketFile.parse(text)
      assert TicketFile.print(ticket) == text
    end
  end

  for {field, value} <- [
        {"id", "../../escape"},
        {"title", "[]"},
        {"type", "unknown"},
        {"status", "done"},
        {"priority", "5"},
        {"priority", "2.0"},
        {"parent", "false"},
        {"blocked_by", "[invalid]"},
        {"related", "no"},
        {"discovered_from", "wrong"},
        {"labels", "[false]"},
        {"created", "2026-02-30"},
        {"closed", "tomorrow"},
        {"close_reason", "[]"}
      ] do
    test "schema rejects #{field}: #{value}" do
      text =
        Regex.replace(~r/^#{unquote(field)}:.*$/m, canonical(), unquote(field <> ": " <> value))

      assert {:error, reason} = TicketFile.parse(text)
      assert reason =~ unquote(field)
    end
  end

  test "chore and supersedes survive canonical round trip; legacy files default to no supersedes" do
    text =
      canonical()
      |> String.replace("type: task", "type: chore")
      |> String.replace("supersedes: []", ~s(supersedes: ["bb-old"]))

    assert {:ok, ticket} = TicketFile.parse(text)
    assert ticket.facts["supersedes"] == ["bb-old"]
    assert TicketFile.print(ticket) == text
    assert {:ok, legacy} = TicketFile.parse(String.replace(canonical(), "supersedes: []\n", ""))
    assert legacy.facts["supersedes"] == []
  end

  test "on hold reason round trips quoted punctuation and rejects missing or blank reasons" do
    text = String.replace(canonical(), "status: open", "status: on_hold")

    for reason <- [nil, "", "  ", 42] do
      input =
        String.replace(
          text,
          "close_reason: null",
          "close_reason: null\non_hold_reason: #{Jason.encode!(reason)}"
        )

      assert {:error, message} = TicketFile.parse(input)
      assert message =~ "on_hold_reason"
    end

    assert {:error, _} = TicketFile.parse(text)
    reason = "Waiting: parts #1\nThen resume"

    input =
      String.replace(
        text,
        "close_reason: null",
        "close_reason: null\non_hold_reason: #{Jason.encode!(reason)}\non_hold_since: 2026-10-21"
      )

    assert {:ok, ticket} = TicketFile.parse(input)
    assert ticket.facts["on_hold_reason"] == reason
    assert TicketFile.print(ticket) == input
    assert {:ok, _} = TicketFile.parse(canonical())

    assert {:error, _} =
             TicketFile.parse(
               String.replace(input, "on_hold_since: 2026-10-21", "on_hold_since: yesterday")
             )
  end

  test "supersedes rejects invalid ids and non-list values" do
    for value <- ["[invalid]", "null", "false", "bb-old"] do
      assert {:error, "supersedes must be a list of ids"} =
               TicketFile.parse(
                 String.replace(canonical(), "supersedes: []", "supersedes: #{value}")
               )
    end
  end

  test "duplicate keys, multiple documents and nested mappings are invalid" do
    assert {:error, _} =
             TicketFile.parse(
               String.replace(canonical(), "priority: 2", "priority: 2\npriority: 3")
             )

    assert {:error, _} = TicketFile.parse("---\n---\nid: bb-abc\n---\n")

    assert {:error, _} =
             TicketFile.parse(
               String.replace(canonical(), "labels: []", "labels: {nested: value}")
             )
  end

  test "handwritten YAML lists and comments become sorted canonical lists" do
    text =
      canonical()
      |> String.replace("labels: []", "labels:\n  - zebra\n  - alpha # comment")
      |> String.replace("title: \"A ticket\"", "title: A ticket # comment")

    assert {:ok, ticket} = TicketFile.parse(text)
    printed = TicketFile.print(ticket)
    assert printed =~ ~s(labels: ["alpha","zebra"])
    assert printed =~ ~s(title: "A ticket")
    assert {:ok, reparsed} = TicketFile.parse(printed)
    assert TicketFile.print(reparsed) == printed
  end

  test "rejects malformed and unknown frontmatter without treating prose as YAML" do
    assert {:error, _} = TicketFile.parse("not frontmatter")

    assert {:error, _} =
             TicketFile.parse(String.replace(canonical(), "priority: 2", "priority: ["))

    assert {:error, reason} =
             TicketFile.parse(String.replace(canonical(), "priority: 2", "surprise: 2"))

    assert reason =~ "surprise"
  end
end
