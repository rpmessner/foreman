# fm-t46: clean launch environments

## Changed

- `lib/foreman/child_environment.ex` adds the pure `clean/1` environment builder and shell-quoted `command/2` executor command. It removes release bin and erts bin PATH entries, `RELEASE_*`, `ERTS_*`, runtime directory variables, `FOREMAN_DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_*`. It preserves other login settings and intended `FOREMAN_*` facts.
- `lib/foreman/session_tmux.ex` uses the builder after interactive login startup through an absolute CLI path. Fresh, resumed, and respawned sessions share this wrapper. Existing tmux client environment clearing and `-N` remain unchanged.
- `lib/foreman/cli.ex` adds the internal `child-environment` command without starting the web application, HTTP client, or Postgres client.
- Builder, CLI, and launch-command tests cover release-shaped environments, stale release PATH entries, literal arguments, login startup contamination, fresh and resumed commands, and helper failure. `test/test_helper.exs` runs the checkout's CLI code rather than requiring an installed update.
- `deploy/systemd/README.md` documents operator startup cleanup and the requirement to install the matching CLI before updating the web release. The unit template needs no change for the observed cause.

Existing uncommitted work was preserved. No commits, installs, deploys, operator configuration edits, or live tmux session changes were made.

## Decision

Request `8be1ac4b-6e1a-4f86-8ea9-4b13e6b1677a` returned `state: answered` with:

> Document operator removal; do not alter user shell configuration

The note is empty. No replacement request was filed. The retained-request background wait loop had already exited when checked after approval.

## Cause and operator action

Read-only investigation found the current live server PID matched `foreman-tmux.service`'s MainPID, 982. Its cgroup ends in `app.slice/foreman-tmux.service`, so this server is unit-owned, not client-started. Inspection of `/proc/982/environ` variable names found no service or release names. Tmux's global environment also lacked `FOREMAN_DATABASE_URL`.

A login shell started with `FOREMAN_DATABASE_URL` removed exported that name again. The pre-restart investigation located the export in `.zshenv.local`, line 4. The resumed investigation independently confirmed the login-shell behavior without printing credential values. This explains contaminated new shells despite a clean server. It does not establish the environment of the older, pre-restart server described in the ticket note.

The approved operator step is to remove shell-global service credential exports and release PATH additions from startup files, keeping service credentials in the service's private environment file. The README gives value-free checks for new windows. `UnsetEnvironment=` cannot prevent later shell startup from exporting a variable again, so no unit edit or server restart is required for this cause. Existing shells retain their environment and should finish their conversations normally.

## Verification

### Scratch launch

Started `/usr/bin/tmux -D -L fm-cleanenv-test`, matching the unit's foreground server mode on a separate socket. Its initial environment contained normal user settings, not service credentials. Called the production `Foreman.SessionTmux.launch/3` with a release-shaped client environment, the real interactive login shell, and this checkout's freshly built CLI as the environment helper. No installed CLI was replaced.

The probe asserted that the launched window resolved `foreman` to `~/.local/bin/foreman`, had no `FOREMAN_DATABASE_URL`, and had no injected release PATH entries. A child shell also asserted CLI resolution and database-variable absence. The scratch server was killed afterwards, and its foreground process exited.

Command: `MIX_ENV=test mix run --no-start /tmp/fm-cleanenv-scratch.exs`, with the scratch directory and fixture environment supplied by the temporary Python driver.

```text
scratch launch: command -v foreman = ~/.local/bin/foreman; database absent; release PATH clean; nested build shell clean
scratch verifier exit: 0
scratch server terminated: True
```

This checks child-process inheritance, not a real pi conversation or an arbitrary manual login window before operator cleanup.

### Regression sensitivity

The restart did not preserve the original failing-first transcript. A resumed mutation check copied the builder and tests to `/tmp`, replaced `clean/1` with the identity transform, and ran `elixir --erl '+S 2:2' /tmp/fm-cleanenv-mutant.exs`. It exited 2 with two assertion failures out of three tests. The release-shaped and stale-PATH tests detected the missing cleanup. This is mutation evidence, not a claim that the original TDD transcript was recovered. The mutation's unused-code warnings were confined to that temporary copy.

### Final gate

`mix precommit` exited 0 with no warnings. It compiled with warnings treated as errors, checked repository hygiene and formatting, and ran the suite against this checkout's isolated test database.

```text
Repository hygiene: no license material or operator paths detected
Finished in 90.7 seconds (6.0s async, 84.6s sync)
5 properties, 750 tests, 0 failures
```

`git diff --check` also passed.

## Sequential self-review

Reviewed against `bb63971ecc2fc25d10c73000857c45516f3d9d86`, including all requested uncommitted changes and the new builder/tests. The committed three-dot diff is empty because the base is HEAD. No subagents were used. The axes ran in the following order.

### Standards

No Critical or Important findings. The builder is a pure transform and the wrapper is process-adapter plumbing, not a new stateful workflow requiring a `Foreman.Fsm` table. Removed one redundant explanatory comment from test setup. Re-ran the gate after that fix. No standards findings remain open. Declined to judge UI conventions because no UI changed.

### Spec

No Critical or Important code findings remain. Tests cover the required environment removals, intended session facts, and launch-command execution. The manual-window dependency was the existing decision, now answered in favor of documenting operator cleanup. That operational step remains unperformed by design. Post-deploy live coordinator and pi acceptance remain for the operator/coordinator because deployment and live-session writes were prohibited.

### Risk

The safety fact is that cleanup applies to newly launched processes while tmux client environment clearing, `-N`, the installed unit, and existing conversations remain unchanged. The scratch production-adapter execution supplies proof level 4. Suite coverage also checks no-server refusal, helper failure, literal prompts, and fresh/resumed startup cleaning.

The matching CLI must be installed before the web release uses the new helper command. This deployment dependency is documented. No Critical or Important code findings remain. Declined to modify the installed unit, exercise live conversations, or deploy under this brief's restrictions.

## Remaining operational work

- Operator removes shell-global service exports as approved. New manual login windows remain contaminated until that step.
- During an authorized deployment, install the matching CLI first, then verify a real launched coordinator and a pi build with the README's value-free checks.

No additional code tickets are proposed. The coordinator owns ticket closure and any authorized commit.
