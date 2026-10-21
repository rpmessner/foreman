You are a build session in foreman (~/dev/utils/fm-age, a git worktree on branch `fm-age`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Three other builds run in sibling worktrees (fm-cleanenv, fm-orphans, fm-deploy, fm-age minus yours); keep shared-file edits small and additive.

## Goal
Initiatives shows each ticket's age (shared human time format); Unplanned sorts newest first and holds only untouched tickets, while parentless work with board activity moves to a Standalone work section. This is a port: the behaviour was built in a work fork, and you re-implement it here cleanly.

## Read first
AGENTS.md, CODING_STANDARDS.md (Phoenix/LiveView rules, checked at review), docs/spec.md sections relevant to this ticket, `foreman show fm-c2w.31` (body and notes). lib/foreman/initiatives.ex and initiatives tree code, lib/foreman_web/live/initiatives_live.ex, the shared time formatting. Reference implementation (read only, for behaviour, not to copy wholesale): the work-fork clone at /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman, commits 62d3a7f and fb71b58 (`git -C /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman show <sha>`). Fork-only ticket files and any text naming people, companies, emails, the work account or work repos must not enter this repo.

## Tickets
fm-c2w.31 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the Initiatives grouping (untouched vs. in flight parentless tickets), age computation, ordering, LiveView rendering. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against bb63971ecc2fc25d10c73000857c45516f3d9d86 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-c2w.31), Risk (Initiatives queries and grouping that other pages reuse). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- 'Untouched' means no board activity (no stage beyond the initial one, no session, no request).
- Section name: Standalone work.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Do not create or remove git worktrees of real repos except scratch repos under /tmp for tests. Use /usr/bin/rm, not rm. Never print secret values or token-file contents.

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-age devserve up` for browser checks and use the printed URL. Confirm `devserve ls --json` shows this worktree with owner `fm-age`; report its unit, URL, database, and browser evidence. The preview has no API token setting yet, so authenticated JSON API calls return 401: check pages in the browser, and say in the report which API paths you could not exercise. If startup or ownership verification fails, report the blocker rather than improvising a server. Leave preview cleanup to coordinator close-out. Screenshot light and dark; be picky about the UI.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-c2w.31 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-c2w.31 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout. Report an unavailable inbox as a blocker rather than guessing. If a wait times out, stay in the wait loop; never write the final report while a question is open.

## Done when
- LiveView tests for age display, Unplanned newest first, and the Standalone work section.
- Before the report: the coordinator's work-string scrub of `git diff` against the base prints nothing (show it in the report).
- Browser screenshots of Initiatives (light and dark) in the preview.
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-age.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-c2w.31 --path docs/sessions/fm-age.md`; warnings never block the marker. Then print FM-AGE DONE alone on the last line.
