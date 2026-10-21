You are a build session in foreman (~/dev/utils/fm-deploy, a git worktree on branch `fm-deploy`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Three other builds run in sibling worktrees (fm-cleanenv, fm-orphans, fm-deploy, fm-age minus yours); keep shared-file edits small and additive.

## Goal
One deploy command for the live board replaces the manual recipe: it refuses a dirty tree or a non-main branch without a flag, builds the prod release and assets, installs it under a new timestamped release id in the releases dir, stops worker and web, switches the `current` link, starts web and worker, runs the existing release smoke against the new release, rolls `current` back and restarts on a failed smoke, then builds and installs the CLI escript. It never stops or restarts the foreman-tmux service (it hosts live sessions).

## Read first
AGENTS.md, CODING_STANDARDS.md (Phoenix/LiveView rules, checked at review), docs/spec.md sections relevant to this ticket, `foreman show fm-ki6` (body and notes). README.md (install and upgrade sections), deploy/systemd/ (units and README), tools/release-smoke.py and tools/release-smoke.exs, mix.exs release config. Today's manual sequence, for reference: `MIX_ENV=prod mix compile; mix assets.deploy; mix release --overwrite`; copy `_build/prod/rel/foreman/.` to `~/.local/lib/foreman/releases/<id>`; stop foreman-worker and foreman-web; `ln -sfn` current; start web and worker; `MIX_ENV=dev mix escript.build` and copy `foreman` to ~/.local/bin.

## Tickets
fm-ki6 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the script's plan and rollback logic tested with stubbed commands (systemctl, the smoke, the link switch) in a temporary releases dir; a test asserting foreman-tmux is never named in a stop/restart. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against bb63971ecc2fc25d10c73000857c45516f3d9d86 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-ki6), Risk (service control, the release directory layout and rollback; the script must be safe to run twice). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- A script in the repo (shell or Elixir/mix task, your call; say why). Releases dir and unit names come from flags with today's defaults.
- A `--dry-run` that prints the plan without acting.
- Keep old releases; pruning is out of scope.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Do not create or remove git worktrees of real repos except scratch repos under /tmp for tests. Use /usr/bin/rm, not rm. Never print secret values or token-file contents. Never run the script for real, never call systemctl start/stop/restart, and never write under ~/.local/lib/foreman or ~/.local/bin; the coordinator runs the first real deploy.

## Browser checks
None needed for this ticket: no UI change. If you change UI after all, use the `devserve` skill as below.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-ki6 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-ki6 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout. Report an unavailable inbox as a blocker rather than guessing. If a wait times out, stay in the wait loop; never write the final report while a question is open.

## Done when
- Tests for the plan, the dirty/branch refusal, the failed-smoke rollback and the never-touch-tmux rule, all with stubs and a temp dir.
- `--dry-run` against the real paths prints the expected plan (read only).
- README upgrade section replaced by the command, with the rollback behaviour stated.
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-deploy.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-ki6 --path docs/sessions/fm-deploy.md`; warnings never block the marker. Then print FM-DEPLOY DONE alone on the last line.
