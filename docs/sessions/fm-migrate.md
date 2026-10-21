# fm-migrate build report

Ticket: fm-i68. Branch: `fm-migrate`. Review base: `de23471eaa0e22af90832d4c24fe12284afa73c8`.
No commits, pushes, deployments, release installs, live service control, or live database queries were performed. No files under the live Foreman configuration directory were read.

## Changed

- `lib/foreman/deploy_lifecycle.ex` declares `:migrating` between install and stop. Migration failure transitions directly to failed, without rollback or service control. Regenerated `docs/machines/deploy_lifecycle.md`.
- `lib/foreman/deploy.ex` runs the installed new release's `bin/foreman eval` before stopping anything. The plan includes migration and its failure behavior. The command adapter preserves explicit output capture.
- `lib/foreman/deploy_migration.ex` builds Ecto.Migrator commands and loads environment files as data. Normal deployment discovers ordered EnvironmentFiles from the installed worker and web units through read-only systemctl properties. Their database settings must agree. `--env-file PATH` overrides discovery.
- Only DATABASE_URL, ECTO_IPV6, and POOL_SIZE from those files reach the migration child. Values never enter command arguments or the deploy process environment. Other deployment commands receive none of the loaded settings. Absent optional database settings are unset in the child instead of inherited from the caller.
- Migration children use the worker role, disable the Phoenix server, unset the web signing secret, capture stdout/stderr, and send Erlang crash dumps to `/dev/null`. Failure messages report the migration phase without forwarding diagnostics or exception messages.
- Dry-run lists pending versions and names through the already-built new release only with an explicit `--env-file`. It otherwise reports that listing is unavailable without reading discovered credentials. The query disables migration-table creation and migration locks; failed or incomplete queries report unavailable rather than none.
- Updated the Mix task help and README. The initial-install instructions now use the deploy command instead of a hidden DATABASE_URL prompt and manual eval. Upgrade instructions explain migration failure, environment loading, dry-run permissions, and backward-compatible schema requirements.

## Verification

All migration tests use temporary files and stubbed commands. One test runs a temporary shell executable as a fake release to verify actual stdout/stderr capture. It never starts a release or connects to Postgres. Dependencies and build artifacts were copied into this worktree from the main checkout before testing; this worktree uses its own test database and `TMPDIR=/tmp/fm-migrate-tests`.

Failing-first evidence:

- The lifecycle test expected migrating after installing and received stopping.
- The command-builder test failed against its separate constant-return stub.
- Execution tests rejected the missing env-file flag, then failed when the environment-loader stub prevented the migration child from running.
- Discovery tests failed when installed-unit loading was unavailable.
- Dry-run tests expected pending names and migration ordering but received the previous plan. Later coverage caught falsely reporting none for incomplete query output.
- Parser tests caught a trailing quote retained on a Unicode URL and missing read-only Ecto query options.
- The crash-dump assertion failed before its child-environment setting was added.

Final focused command:

```sh
TMPDIR=/tmp/fm-migrate-tests mix test test/foreman/deploy_test.exs test/foreman/deploy_migration_test.exs test/foreman/fsm_docs_test.exs
```

Result: **54 tests, 0 failures**. Coverage includes ordered commands, migration failure preserving current and running services, no rollback on migration failure, captured output and Logger suppression, settings isolated to the migration child, explicit override, installed-unit discovery, conflicting settings, malformed files, Unicode values, dry-run pending/none/unavailable outcomes, and existing rollback behavior.

Mutation check: routing migration failure through rollback caused the failure-safety test to fail on unexpected `Rollback succeeded`. The mutation was removed. The focused suite and full gate then passed.

`mix foreman.deploy --dry-run --allow-dirty --allow-non-main` on this worktree exited 0 and printed build, copy/install, migrate, stop, switch, start, smoke, then CLI installation. It reported pending migrations unavailable without an explicit env-file. No deployment effects or credential reads occurred. The override flags are required for this uncommitted feature worktree.

`git diff --check` passed.

## Sequential review

Reviewed the requested base against the working tree, including new files. HEAD equals the base and the committed three-dot diff is empty because this build forbids commits. The review therefore covered the explicitly requested uncommitted implementation. Axes ran sequentially in this session without subagents.

### Standards

Ready. No final findings. The new lifecycle state, success transition, and failure transition are on the declared Foreman.Fsm table. The executor interprets effects; environment parsing and command construction add no ad hoc lifecycle state. Reviewed AGENTS.md, CODING_STANDARDS.md, and the house baseline. No Standards fixes were needed. UI rules were not judged because no UI changed.

### Spec

Ready for coordinator verification. No final code findings. All requested build-time acceptance items have executable coverage or the worktree dry-run evidence above. During implementation, fixed the read-only query omission: Ecto's default migration listing can create schema_migrations, so the generated query now skips table creation and locking. Also fixed incomplete-query output being mistaken for no pending migrations.

The first live deployment shipping fm-c2w.30 was not judged or attempted because this build explicitly prohibits deployment. It remains the coordinator's operational check, not a completed claim here.

### Risk

Ready. Fixed an Important credential-persistence risk by disabling child crash dumps. The regression asserts the environment setting. A temporary executable proves stdout and stderr containing synthetic credentials are captured instead of streamed. Earlier hardening also fixed quoted Unicode handling and prevented ambient optional database settings from overriding the file contract.

The safety fact reaches proof level 4: a failed migration never enters service-control or link-switch effects, and loaded database settings reach only the migration child. Stubbed deploy tests assert both facts; the mutation check demonstrates detection of a wrong failure transition. Existing stop/start/smoke rollback tests remain green.

No final Critical or Important findings remain. Declined live systemd behavior, host readiness, and live schema compatibility because this build cannot exercise them. Applied migrations are not rolled back; README requires compatibility with the still-running old release. Complex environment-file syntax and escaped discovery paths fail closed, with the supported subset and override documented.

## Final gate

After the review fix and removal of the mutation:

```text
TMPDIR=/tmp/fm-migrate-tests mix precommit
Repository hygiene: no license material or operator paths detected
Running ExUnit with seed: 275869, max_cases: 16
Generated escript foreman with MIX_ENV=test
Finished in 89.8 seconds (5.0s async, 84.7s sync)
5 properties, 796 tests, 0 failures
```

Exit 0, zero warnings. The earlier full gate also passed with 796 tests and zero failures.

## Coordinator follow-up

Run the first authorized deployment from integrated main, including fm-c2w.30, and verify the live service and migration state. Keep fm-i68 open until that operational acceptance is complete. No additional tickets proposed. No approval question is open.
