You are a build session in foreman (~/dev/utils/fm-onesession, a git worktree on branch `fm-onesession`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's.

## Goal
Ticket fm-c2w.32: optional `board.tmux_session` in foreman.toml. When set, every board-launched session (planning sessions, the coordinator, epic coordinators) opens as a window of that one tmux session on the board's tmux server instead of a session named after its project. Unset keeps today's behaviour exactly.

## Read first
AGENTS.md; `foreman show fm-c2w.32`; docs/coordinator.md; lib/foreman/session_tmux.ex and lib/foreman/sessions.ex; the config schema.
The reference implementation from another checkout is in docs/fork-e005d71.diff.txt (code only). Port the logic onto today's main, which has moved a lot since (clean child environment wrapper, @foreman-pane marker, epic coordinators, pane Focus). Write every comment, doc line, test name and commit-facing prose fresh in your own words; copy nothing but code shape. Delete docs/fork-e005d71.diff.txt before you finish.

## Must hold
- Every place that resolves a session's window by project name keeps working in one-session mode: launch, reuse/relaunch, observe, Continue, waiting targets, Focus for pane builds (`focus_build` currently matches session_name == project), the attach command shown on the board, and the singleton coordinator. Windows from different projects must not collide by name in the shared session; decide the window naming and record it in docs/coordinator.md.
- Config rejects invalid values (empty, characters tmux treats as target separators such as `:` and `.`).

## Tickets
Start with `foreman update fm-c2w.32 --status in_progress`. Report new work instead of filing it.

## Skills
- `tdd` at these seams: config validation; SessionTmux launch/observe/focus with a scratch tmux server (`-L` socket under /tmp) in both modes; Sessions launch/reuse in one-session mode.
- `verify-before-claiming` before the report.
- `code-review` on your diff against c9d59f6: Standards, Spec (fm-c2w.32 plus Must hold), Risk (a wrong tmux target could send keys to another project's window). One axis after another; no subagents. Fix every Critical and Important finding, then rerun the gate.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server, ~/.config/foreman or the skills repo. Use /usr/bin/rm, not rm. No UI changes are expected; if you make one, use `FOREMAN_SESSION=fm-onesession devserve up` and screenshot light and dark.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-c2w.32 "<milestone; next step>"` at milestones. For a genuine user decision run `foreman ask decision fm-c2w.32 --question ... --option ... --recommendation ...`, then `foreman wait <id> --timeout 7200` in your shell; resume only on `state: answered` and re-wait after a timeout.

## Done when
Every acceptance item and Must hold item holds with evidence (scratch tmux transcripts for both modes); `mix precommit` green with zero warnings.

## Report back
Write docs/sessions/fm-onesession.md: what changed, window naming, evidence, review findings per axis, anything open, final gate output. Send `foreman report fm-c2w.32 --path docs/sessions/fm-onesession.md` best-effort, then print FM-ONESESSION DONE alone on the last line.
