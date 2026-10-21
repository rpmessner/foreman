You are a build session in foreman (~/dev/utils/fm-sheetfix, a git worktree on branch `fm-sheetfix`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Other builds run in sibling worktrees; keep shared-file edits small.

## Goal
The ticket sheet's Overview names the ticket-file fields correctly (no 'Beads fields' heading: tickets are files now) and shows every time on the sheet in the shared human format (just now, 2 min ago) with the full time on hover, instead of raw ISO strings such as 2026-10-20T10:00:00Z.

## Read first
AGENTS.md, CODING_STANDARDS.md, `foreman show fm-11q`. lib/foreman_web/components/ticket_detail.ex and the shared time formatter it already uses elsewhere (RelativeTime / TicketDetail.timestamp), the house rules at the top of AGENTS.md (times use the shared human format).

## Tickets
fm-11q (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the Overview's field rendering (heading text and each time-valued field) through the existing ticket sheet LiveView tests. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against de23471eaa0e22af90832d4c24fe12284afa73c8 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-11q), Risk (the sheet is shared by Initiatives, the epic page and Needs you). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- Heading text: "Ticket fields". Keep the field list otherwise unchanged.
- Every time-valued field on the sheet goes through the shared formatter; date-only values show the date.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman (read nothing there either), ~/.config/devserve or the skills repo. Use /usr/bin/rm, not rm. Never print secret values or environment-file contents. Run mix test with your own TMPDIR (e.g. `TMPDIR=/tmp/<window>-tests`): concurrent suites in sibling worktrees collide on shared temp dirs.

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-sheetfix devserve up` (run `mix deps.get` first if needed) and use the printed URL. Confirm `devserve ls --json` shows this worktree with owner `fm-sheetfix`; report its unit and URL. Leave preview cleanup to coordinator close-out. Screenshot the ticket sheet light and dark.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-11q "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-11q --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout; never write the final report while a question is open. Report an unavailable inbox as a blocker rather than guessing.

## Done when
- LiveView tests for the heading and formatted times (including hover title with the full time).
- Screenshots light and dark of a ticket sheet with a created-at value.
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-sheetfix.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-11q --path docs/sessions/fm-sheetfix.md`; warnings never block the marker. Then print FM-SHEETFIX DONE alone on the last line.
