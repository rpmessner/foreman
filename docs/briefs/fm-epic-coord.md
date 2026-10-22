You are a build session in foreman (~/dev/utils/fm-epic-coord, branch fm-epic-coord, a worktree of ~/dev/utils/foreman). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's.

## Goal
Ticketed epics that are not done or abandoned can be launched from the board as an epic coordinator: a Claude session in the project's tmux session on `tmux -L foreman`, one window per epic, tracked like planning sessions (Focus, Relaunch, parking), whose opening prompt makes it own that epic's builds and dispatch them as panes in its own window. Focus on a building ticket dispatched in pane mode selects that pane. Full scope, notes and acceptance: ticket fm-3c3.8.

## Read first
AGENTS.md; `foreman show fm-3c3.8` (body and notes); the launcher epic `foreman show fm-3c3`; docs/coordinator.md; docs/sessions/fm-coordinator.md and docs/sessions/fm-pane-env.md (the two slices before this); lib/foreman/sessions.ex (launchable?/1, launch, relaunch), session_prompt.ex, session_machine.ex, session_tmux.ex, the Initiatives and epic LiveViews; the dispatch skill's pane mode (~/dev/utils/skills/skills/dispatch/SKILL.md, scripts/pi-window --pane, pi-wait --pane) — read only, do not edit the skills repo.

## Tickets
fm-3c3.8 (ticket files). Start with `foreman update fm-3c3.8 --status in_progress`. The coordinator files new tickets and closes this one; report new work instead of filing it.

## Skills
- `tdd` at these seams: launchable?/1 for ticketed/derived-stage epics vs done/abandoned; the epic opening prompt; Focus resolving a `%pane` window value to select-window + select-pane; LiveView controls on the epic row and epic page.
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against 9392b0c before printing the marker: Standards, Spec (fm-3c3.8), and Risk (session launching). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- User 2026-10-18: ticketed epics get Launch; this reverses the launcher spec's non-goal about ticketed epics.
- The epic coordinator owns only its epic: orient on it, dispatch its ready tickets with the dispatch skill in pane mode (`pi-window --pane`), close out under the usual rules (review, commit only when the user asks, board requests for push/PR/merge). The main coordinator keeps one window per build and is unchanged.
- The prompt names skills instead of restating them; keep it short.
- Pane builds report their `%pane-id` through the dispatch `window` field; FOREMAN_SESSION is the logical build name.
- State goes through the existing session machine (house FSM DSL); extend it rather than adding ad-hoc state.
- UI copy: labels and instructions fine, no taglines.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live `-L foreman` server, the installed release, ~/.config/foreman or the skills repo. Stub claude and pi; scratch tmux only.

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-epic-coord devserve up` for browser checks and use the printed URL. Confirm `devserve ls --json` shows this worktree with owner `fm-epic-coord`; report its unit, URL, database, and browser evidence. If startup or ownership verification fails, report the blocker rather than improvising a server. Leave preview cleanup to coordinator close-out.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-3c3.8 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-3c3.8 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout. Report an unavailable inbox as a blocker rather than guessing.

## Done when
Every fm-3c3.8 acceptance item holds with evidence (scratch tmux transcript of an epic launch with the stub claude's argv and prompt; pane Focus transcript; screenshots light/dark at 1440 and 390 of the epic row and epic page controls, inspected for layout); `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-epic-coord.md: what changed, evidence, review findings per axis with what you fixed and what you left open, anything else open, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-3c3.8 --path docs/sessions/fm-epic-coord.md`; warnings never block the marker. Then print FM-EPIC-COORD DONE alone on the last line.
