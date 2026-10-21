# fm-deploy build report

Ticket: fm-ki6. Branch: `fm-deploy`. Review base: `bb63971ecc2fc25d10c73000857c45516f3d9d86`.
No commits, pushes, live deployments, service control, or release/CLI installs were performed.

## Changed

- Added `mix foreman.deploy` in `lib/mix/tasks/foreman.deploy.ex`, backed by `lib/foreman/deploy.ex`.
- Chose a Mix task so the deployment lifecycle uses the existing `Foreman.Fsm` DSL rather than separate shell state logic. `lib/foreman/deploy_lifecycle.ex` declares the phases and failure transitions. Its generated diagram and matrix have a golden test.
- Added checkout guards, override flags, dry-run, configurable release directory/service names/CLI destination, timestamped release copies, deployment locking, atomic `current` switching, and rollback.
- Smoke runs against the installed new release. CLI installation follows successful smoke and uses atomic replacement. A CLI failure retains the healthy new release. Old releases remain untouched.
- `tools/release-smoke.py` accepts `--release`; its default remains the build output. The probe and disposable-database behavior are unchanged.
- Replaced README upgrade steps with the command, rollback behavior, migration limitations, and interrupted-deployment recovery instructions.

Mix can compile checkout tooling before running the task. Dry-run performs no deployment writes or service control. This command upgrades an existing installation; it does not provision services or migrate the live database.

## Evidence

- Failing-first deployment test returned `{:error, :not_implemented}` where the dry-run plan was expected. Subsequent execution tests failed against the execution stub. The installed-path smoke test failed with `AssertionError` before argument selection was implemented.
- Review regressions failed before their fixes: CLI failure omitted `Smoke passed`; equivalent service names were accepted; `--web-unit=--all` reached the stubbed systemctl command. No real systemctl command was executed.
- `mix test test/foreman/deploy_test.exs test/foreman/fsm_docs_test.exs` passed with **41 tests, 0 failures**. Deployment tests use temporary directories and stubbed build, service and smoke commands. Link operations run only inside those directories.
- Tests cover ordered plan/effects, dirty and branch refusal/overrides, smoke rollback, initial stop/start failures, link failure, explicit rollback failure, CLI failure, repeated deployment, retained releases, lock refusal, forbidden tmux/glob/option-like units, and equivalent unit names.
- Mutation check: making rollback select the new release instead of the previous one caused **4 failures**. Restoring the implementation returned the focused suite to green.
- `mix foreman.deploy --dry-run --allow-dirty --allow-non-main` printed the expected plan for the real default paths. It named only web and worker services and selected the new installed path for smoke. It did not change those paths.
- `python3 tools/release-smoke.py --help` lists `--release`. `git diff --check` passed.

The first full gate had one unrelated LiveView token-clock failure in `ForemanWeb.SessionLaunchTest`, `sheet offers Launch only for unplanned tickets`. Its immediate file retry passed, **5 tests, 0 failures**. No clock workaround or unrelated source was changed. The final full gate passed.

## Review

Reviewed uncommitted additions and the tracked diff against the named base. HEAD equals that base, so the committed three-dot diff is empty. Axes ran sequentially in this session without subagents, followed by fixes, sequential rechecks, and the full gate.

### Standards

Fixed an Important stale-tooling risk by using the task's standard compile requirement. Added the generated FSM diagram/matrix and golden coverage required by spec Decision 6. All phase transitions remain on the declared machine; the executor interprets returned effects.

Final findings: none. Declined UI review because no UI changed. Ready.

### Spec

Fixed Important omissions in failure output and verification. Terminal errors now report the smoke outcome, including CLI failures after a passing smoke. Tests assert ordered deployment commands, the exact rollback sequence, and modeled running services after recovery.

Final code findings: none. The ticket's first-real-deploy acceptance remains coordinator-owned, as this build explicitly prohibited deployment. Ready for that check.

### Risk

Fixed a Critical unit-option injection risk at `lib/foreman/deploy.ex:78`: names beginning with a hyphen could become systemctl options. Also fixed equivalent unit names and added stop/start/rollback failure coverage. Literal-name validation rejects options, globs and tmux names before effects.

The safety fact is proven at level 4 by executable tests: failed smoke restores the exact previous link before the final restart, while service control is restricted to validated web/worker names. Repeat deployment preserves earlier releases and replaces the CLI safely.

Final code findings: none. Host service readiness, custom unit dependency graphs, process termination/power loss, and live schema compatibility were not judged by isolated package tests. README documents these operational limits. No live-health claim is made.

## Final gate

`mix precommit` exited 0 after the review fixes, with zero warnings:

```text
Repository hygiene: no license material or operator paths detected
Running ExUnit with seed: 887653, max_cases: 16
Generated escript foreman with MIX_ENV=test
Finished in 89.9 seconds (7.6s async, 82.3s sync)
5 properties, 760 tests, 0 failures
```

## Coordinator follow-up

Run the first real deploy from the integrated clean main checkout and confirm the live board serves the new release. That is the remaining operational acceptance check, not a claim of this report. No additional tickets proposed. Keep fm-ki6 open until that verification.
