You are a build session in foreman (~/dev/utils/fm-history, a git worktree on branch `fm-history`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's.

## Goal
Ticket fm-c2w.21: on the epic page, EPIC STAGE HISTORY reads cleanly. Today each event's facts (Title, Session, Spec, Epic) put labels on one line and values far right or below with big gaps, columns have uneven widths, and stray rules sit underneath. Each event should read as a compact card or row: event name and transition, actor and age, then label/value pairs aligned in a label column with the value beside it.

## Read first
AGENTS.md, CODING_STANDARDS.md, `foreman show fm-c2w.21`. Look at the current page in a preview before changing anything (fm-3c3 is a good example: several events with Title/Session/Spec/Epic facts).

## Skills
- `tdd` at the LiveView seam for the history markup structure (pairs grouped per event, labels and values in order).
- `verify-before-claiming` before the report.
- `code-review` on your diff against 87e657f: Standards, Spec, Risk. One axis after another, no subagents. Fix every Critical and Important finding.

## Browser checks
Use the `devserve` skill: `FOREMAN_SESSION=fm-history devserve up`, confirm `devserve ls --json` shows owner `fm-history`. Seed epics whose history has long values (long titles, long spec paths) and several facts. Screenshot light and dark at 1440 and 390 before and after; be picky about alignment, wrapping and spacing. Leave preview cleanup to the coordinator.

## Tickets
Start with `foreman update fm-c2w.21 --status in_progress`. Report new work instead of filing it.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server, ~/.config/foreman or the skills repo. Use /usr/bin/rm, not rm.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress <ticket> "<milestone; next step>"` at milestones. For a genuine user decision run `foreman ask decision <ticket> --question ... --option ... --recommendation ...`, then `foreman wait <id> --timeout 7200` in your shell; resume only on `state: answered`, re-wait after a timeout.

## Done when
The acceptance in fm-c2w.21 holds with screenshots you inspected; `mix precommit` green with zero warnings.

## Report back
Write docs/sessions/fm-history.md: what changed, before/after screenshots (linked), review findings per axis, final gate output. Send `foreman report fm-c2w.21 --path docs/sessions/fm-history.md` best-effort, then print FM-HISTORY DONE alone on the last line.
