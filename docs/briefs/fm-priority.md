You are a build session in foreman (~/dev/utils/fm-priority, a git worktree on branch `fm-priority`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. One other build (fm-cleanenv) runs in a sibling worktree on session launch code; keep shared-file edits small.

## Goal
Ticket priority on the board: P0-P4 badges on Initiatives rows, request cards and the ticket sheet. A board edit is a Postgres override, declared as a Foreman.Fsm machine, that clears itself once the ticket file's priority catches up. Ready lists, Initiatives and Needs you sort by effective priority. "Jump to front" puts a ticket ahead of its priority band, and `foreman ls --overlay` exposes overrides and jumps. This is a port: the behaviour was built in a work fork, and you re-implement it here cleanly.

## Read first
AGENTS.md, CODING_STANDARDS.md, docs/spec.md (ticket, overlay and Needs you sections), `foreman show fm-c2w.30`. lib/foreman/stage.ex, requests.ex, ticket_cli.ex, agent_commands.ex, initiatives*.ex, foreman_web/components/ticket_detail.ex and request_card.ex, live/{epic,initiatives,needs_you,pull_requests}_live.ex, the Foreman.Fsm DSL and an existing machine doc in docs/machines/. Recent reports: docs/sessions/fm-age.md and docs/sessions/fm-orphans.md (both just merged; Initiatives grouping and the request lifecycle changed).
Reference implementation (read only, for behaviour, not to copy wholesale): the work-fork clone at /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman, commit 5c5b6a1 (`git -C /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/forks/foreman show 5c5b6a1`). Its ticket files, commit messages and any text naming people, companies, emails, accounts or work repos must not enter this repo.

## Tickets
fm-c2w.30 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the override machine (set, change, clear when the file catches up, jump to front), effective-priority ordering, `foreman ls --overlay` output, LiveView badges and sorting on Initiatives and Needs you. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against 8398058b0917defedd0c4749c0ca24509137c1e4 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-c2w.30), Risk (the migration, ordering used by other pages, overlay CLI output consumed by orient/dispatch scripts). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- The migration for the overrides table is approved by the user (2026-10-21) as part of this port; keep it to what overrides and jumps need.
- The app still never writes ticket files: overrides live in Postgres only, and clear when the file's priority equals the override.
- Badge copy is the label only (P0-P4); no tooltips explaining the feature.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Use /usr/bin/rm, not rm. Never print secret values or token-file contents. Run mix test with your own TMPDIR (e.g. `TMPDIR=/tmp/fm-priority-tests`): concurrent suites in sibling worktrees collide on shared temp dirs.

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-priority devserve up` for browser checks and use the printed URL (run `mix deps.get` first if dependencies are missing). Confirm `devserve ls --json` shows this worktree with owner `fm-priority`; report its unit, URL, database, and browser evidence. The preview has no API token setting yet, so authenticated JSON API calls return 401: check pages in the browser, and say in the report which API paths you could not exercise. If startup or ownership verification fails, report the blocker rather than improvising a server. Leave preview cleanup to coordinator close-out. Screenshot light and dark at 1440 and 390 px; be picky about the UI.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-c2w.30 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-c2w.30 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout; never write the final report while a question is open. Report an unavailable inbox as a blocker rather than guessing.

## Done when
- Every fm-c2w.30 acceptance item holds with evidence except the post-deploy live check (the coordinator does that after merge).
- Before the report: `git diff 8398058b0917defedd0c4749c0ca24509137c1e4 | grep -i -E -f /tmp/claude-1000/-home-rpmessner-dev-music/b034bdad-1084-4b73-8da7-bdfb1f4e577b/scratchpad/scrub.pat` and the same over untracked new files print nothing; show the commands and empty output in the report (do not copy the pattern file's contents into the repo or the report).
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-priority.md: what changed, the machine table, the migration, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-c2w.30 --path docs/sessions/fm-priority.md`; warnings never block the marker. Then print FM-PRIORITY DONE alone on the last line.
