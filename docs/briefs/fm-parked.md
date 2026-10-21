You are a build session in foreman (~/dev/utils/fm-parked, a git worktree on branch `fm-parked`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Other builds run in sibling worktrees; keep shared-file edits small.

## Goal
A ticket status for work deliberately set aside, with a required reason: the CLI refuses it without a reason, the home page shows such tickets in their own section with a badge, and they never count as stale. This is a port: the behaviour was built in a work fork, and you re-implement it here cleanly.

## Read first
AGENTS.md, CODING_STANDARDS.md, docs/spec.md (ticket files and statuses), `foreman show fm-c2w.33`. lib/foreman/ticket_status_machine.ex and its doc, ticket_file(s).ex, ticket_cli.ex, initiatives.ex and initiatives filters, config/schema.ex and priv/foreman.defaults.toml, foreman_web/components/ticket_detail.ex, live/initiatives_live.ex, beads/export.ex. Also how sessions.ex and planning_session.ex use "parked" for planning sessions today. Recent reports: docs/sessions/fm-age.md and fm-priority.md (Initiatives grouping and priority ordering just changed).
Reference implementation (read only, for behaviour, not to copy wholesale): the work-fork clone at /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman, commit 79be572 (`git -C /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman show 79be572`). Its ticket files, commit messages and any text naming people, companies, emails, accounts or work repos must not enter this repo.

## Tickets
fm-c2w.33 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the ticket status machine's new state and transitions, CLI refusal without a reason, file round trip of the reason, Initiatives grouping and stale exclusion, the sheet and badge. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against e6050831717268a33984d8ec14ea936e71905452 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-c2w.33), Risk (ticket file format compatibility with older CLIs and foreman check, Initiatives queries other pages reuse). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- Ticket and planning-session parking must never read the same in UI or docs. Choose the ticket status name and labels to keep them distinct (e.g. a ticket status "on hold" if "parked" would collide on screen); record the choice and why in the report. Ask through the board only if both options would change existing user-visible session text.
- The reason is stored in the ticket file; the app still never writes ticket files (the CLI does).
- Badge and section copy are labels only.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Use /usr/bin/rm, not rm. Never print secret values. Run mix test with your own TMPDIR (`TMPDIR=/tmp/fm-parked-tests`).

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-parked devserve up` (run `mix deps.get` first if needed) and use the printed URL. Confirm `devserve ls --json` shows this worktree with owner `fm-parked`; report its unit, URL and browser evidence. API calls return 401 in previews (no token yet); check pages in the browser. Leave preview cleanup to coordinator close-out. Use Playwright with `NODE_PATH=/tmp/bb-filters-browser/node_modules`; screenshot Initiatives and the sheet light and dark at 1440 and 390 px; be picky about the UI.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-c2w.33 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-c2w.33 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout; never write the final report while a question is open. Report an unavailable inbox as a blocker rather than guessing.

## Done when
- Every fm-c2w.33 acceptance item holds with evidence except the post-deploy live check.
- Before the report: `git diff e6050831717268a33984d8ec14ea936e71905452 | grep -i -E -f /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/scrub.pat` and the same over untracked new files print nothing; show the commands and empty output (never copy the pattern file's contents into the repo or report).
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-parked.md: what changed, the status name chosen and why, the machine rows, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-c2w.33 --path docs/sessions/fm-parked.md`; warnings never block the marker. Then print FM-PARKED DONE alone on the last line.
