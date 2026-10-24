You are a build session in foreman (~/dev/utils/fm-cleanenv, a git worktree on branch `fm-cleanenv`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Three other builds run in sibling worktrees (fm-cleanenv, fm-orphans, fm-deploy, fm-age minus yours); keep shared-file edits small and additive.

## Goal
Sessions foreman launches, and windows created in its tmux server, start with a clean environment: no foreman release PATH entries (release bin and erts bin dirs), no RELEASE_*/erts variables, no FOREMAN_DATABASE_URL, SECRET_KEY_BASE or PHX_*, while keeping the user's login PATH and the FOREMAN_* session facts foreman sets on purpose. Today a launched coordinator's `foreman` resolves to a release's start/daemon script instead of the CLI, and every window in the server inherits the live database URL.

## Read first
AGENTS.md, CODING_STANDARDS.md (Phoenix/LiveView rules, checked at review), docs/spec.md sections relevant to this ticket, `foreman show fm-t46` (body and notes). lib/foreman/session_tmux.ex (the env strip near the launch command, the tmux runner), deploy/systemd/ (foreman-tmux unit and README), lib/foreman/cli_transport.ex (the only reader of FOREMAN_DATABASE_URL in the CLI). Find out how the running tmux server got FOREMAN_DATABASE_URL in its own process environment (read-only: /proc/<pid>/environ names only, never values) and whether a client-started server or the unit causes it.

## Tickets
fm-t46 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the child-environment builder (a pure function from an environment map to the launch environment), and the launch command it produces. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against bb63971ecc2fc25d10c73000857c45516f3d9d86 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-t46), Risk (launching sessions, the tmux server unit, anything that could start or kill the live tmux server). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- Prefer one pure environment builder used by every launch path over string-built `unset` loops.
- If the server-level leak needs a unit change (e.g. `UnsetEnvironment=` or `env -i` with an allowlist in ExecStart), change the template in deploy/systemd/ and document the one-time operator step; do not restart or modify the installed unit yourself.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Do not create or remove git worktrees of real repos except scratch repos under /tmp for tests. Use /usr/bin/rm, not rm. Never print secret values or token-file contents. Never kill, restart or send keys to the `-L foreman` server or its sessions; use your own `-L fm-cleanenv-test` server for experiments.

## Browser checks
None needed for this ticket: no UI change. If you change UI after all, use the `devserve` skill as below.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-t46 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-t46 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout. Report an unavailable inbox as a blocker rather than guessing. If a wait times out, stay in the wait loop; never write the final report while a question is open.

## Done when
- Unit tests: a release-shaped environment in, a clean one out (no release PATH entries, no RELEASE_*/erts vars, no FOREMAN_DATABASE_URL/SECRET_KEY_BASE/PHX_*), intended FOREMAN_* facts kept.
- A scratch tmux server (`tmux -L fm-cleanenv-test`, killed afterwards) started the way the fixed unit/launch path starts it: a launched window's `command -v foreman` is ~/.local/bin/foreman and FOREMAN_DATABASE_URL is absent. Evidence in the report.
- The cause of the server-level leak stated with evidence, and the operator step (if any) written in deploy/systemd/README.md.
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-cleanenv.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-t46 --path docs/sessions/fm-cleanenv.md`; warnings never block the marker. Then print FM-CLEANENV DONE alone on the last line.
