# fm-11q build report

## Changes
- Renamed the Overview heading to “Ticket fields” regardless of ticket source.
- Routed created, updated, and closed time-valued ticket fields through the existing `TicketDetail.timestamp/1` formatter, which supplies relative text and a full ISO `title`. Date-only fields remain date-only.
- Added LiveView coverage for heading text, multiple formatted times, and hover-title values.

## Evidence
- `TMPDIR=/tmp/fm-sheetfix-tests mix test test/foreman_web/live/initiatives_live_test.exs`: 48 tests, 0 failures.
- `TMPDIR=/tmp/fm-sheetfix-tests mix precommit`: 784 tests, 0 failures; repository hygiene passed. First full run had one isolated LiveView process failure; targeted rerun and subsequent full rerun passed.
- `git diff --check`: passed.
- Preview: `devserve-foreman-fm_sheetfix-39cd9f86e6c7.service`, `http://127.0.0.1:4880`; `devserve ls --json` confirms owner `fm-sheetfix` and this worktree.
- Screenshots (coordinator, preview with live-data copy): [light](../acceptance/fm-sheetfix/sheet-light.png), [dark](../acceptance/fm-sheetfix/sheet-dark.png). The created date shows 'Oct 21' with the date as hover.

## Review against de23471eaa0e22af90832d4c24fe12284afa73c8
- Standards: No new state or lifecycle introduced; existing shared timestamp formatter reused. No findings.
- Spec (fm-11q): Heading and all timestamp-valued fields implemented and tested. Screenshot acceptance remains open as noted above.
- Risk: Sheet is shared by Initiatives, epic page, and Needs you. Change is confined to the shared field rendering; focused Initiatives sheet tests and full precommit pass. No additional regressions identified.

## Proposed follow-ups
- Capture ticket-sheet light/dark screenshots with a created-at value; inspect the shared sheet in the epic and Needs you contexts.

## Final gate
`TMPDIR=/tmp/fm-sheetfix-tests mix precommit` — passed: 5 properties, 784 tests, 0 failures; hygiene passed.

## Coordinator completion (2026-10-21)
The first pass rendered file-ticket dates as relative time from padded midnight ('8 h ago'). The build's second attempt changed ticket-file normalization (broke 6 tests) and then stalled. The coordinator finished it in the display layer only: file tickets' created/closed show the stored date (`%b %-d`, hover YYYY-MM-DD); real timestamps keep relative time with the full time on hover. Tests use the projection's real padded value. `TMPDIR=/tmp/fm-sheetfix-tests mix precommit`: 785 tests, 0 failures.
Follow-up seen: the Initiatives filter still labels the status select 'Beads status'.
