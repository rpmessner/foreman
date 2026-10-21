You are a build session in foreman (~/dev/utils/fm-migrate, a git worktree on branch `fm-migrate`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Other builds run in sibling worktrees; keep shared-file edits small.

## Goal
`mix foreman.deploy` runs pending database migrations with the newly built release before it stops anything: build, install, migrate with the new release, stop, switch, start, smoke. A migration failure stops the deploy with the old release still current and running. `--dry-run` lists pending migrations. No secret value is ever printed or logged.

## Read first
AGENTS.md, CODING_STANDARDS.md, `foreman show fm-i68`. lib/foreman/deploy.ex, lib/foreman/deploy_lifecycle.ex, lib/mix/tasks/foreman.deploy.ex, test/foreman/deploy_test.exs, docs/sessions/fm-deploy.md (the build that made the command), README.md (Build, migrate and enable: the manual `bin/foreman eval` Ecto.Migrator step), deploy/systemd/ (which environment files the units load).

## Tickets
fm-i68 (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the lifecycle's new migrate phase and its failure transition, the plan order, dry-run listing, the migration command builder (environment passed to the child process, never on the command line or in output). Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against de23471eaa0e22af90832d4c24fe12284afa73c8 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-i68), Risk (service control, rollback, and secret handling: the database settings must reach only the migration child process). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- The migration runs the new release's `bin/foreman eval` with Ecto.Migrator, with the same database settings the services use. Get them by loading the environment file(s) the systemd units name (paths from the installed unit files or flags with today's defaults), parsed as KEY=VALUE data, passed only in the child's environment; never `source` them and never print values. Add a `--env-file PATH` flag that overrides discovery.
- Dry-run may list pending migration names by asking the new release, but must not connect if that needs secrets you were not given; if it cannot list them, it says so.
- Tests use stubs and temp dirs only; never read real files under ~/.config/foreman.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman (read nothing there either), ~/.config/devserve or the skills repo. Use /usr/bin/rm, not rm. Never print secret values or environment-file contents. Run mix test with your own TMPDIR (e.g. `TMPDIR=/tmp/<window>-tests`): concurrent suites in sibling worktrees collide on shared temp dirs.

## Browser checks
None needed: no UI change.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-i68 "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-i68 --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout; never write the final report while a question is open. Report an unavailable inbox as a blocker rather than guessing.

## Done when
- Tests: plan order with migrate before stop; migration failure leaves current and services untouched and reports the phase; env-file values reach only the child environment and never appear in output (assert on captured output); `--env-file` override; dry-run behaviour.
- README's manual migration step replaced by the command, with the failure behaviour stated.
- `mix foreman.deploy --dry-run` on this worktree prints the new plan (read only).
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-migrate.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-i68 --path docs/sessions/fm-migrate.md`; warnings never block the marker. Then print FM-MIGRATE DONE alone on the last line.
