# fm-c2w.32 build report

## Changes

`board.tmux_session` is optional. The schema accepts a leading letter or digit followed by letters, digits, underscores or hyphens. Empty strings, dots, colons, spaces, target prefixes and non-string values fail validation.

`SessionTmux` reads the board configuration once per routing lookup. Shared mode uses one session on the existing board server. Planning and epic windows are named `project/ticket`; the singleton is `__foreman__/coordinator`. A draft can therefore be `alpha/draft:arrangement`. Unset mode retains project sessions, ticket window names and the singleton's `coordinator` session.

Window IDs and conversation UUIDs still control recovery and relaunch, including older windows retained after an ended conversation. Shared build Focus additionally requires the window's `@foreman-project` marker. Waiting controls use the marked coordinator pane instead of an active build pane. Both waiting controls and Continue reject a pane marker pointing outside the identified window.

Two projects can race to create the shared session. Only tmux's duplicate-session response retries as new-window; other failures remain errors. The clean child-environment wrapper, automatic-rename handling and launch hooks remain intact.

`docs/coordinator.md` records the naming and configuration rules. The supplied reference diff was deleted. There are no UI changes.

## Test-first evidence

- `mix test test/foreman/config_test.exs` first failed because `board.tmux_session` was unknown. After the schema change, 19 tests passed.
- `mix test test/foreman/session_tmux_routing_test.exs` first failed because shared mode produced `alpha`, `beta` and `coordinator` sessions instead of `board`. The default-mode case passed.
- For the Sessions seam, routing was temporarily restored to the unset behavior before running the new test. It failed on `sample|x-1` versus `board|sample/x-1`. Restoring routing made recovery and relaunch pass. Additional review coverage exercises initial planning, epic and singleton launches through Sessions.
- A waiting-target test failed in both modes because Open session selected the active build pane. Using `@foreman-pane` corrected the target.
- Safety regressions first failed on a foreign pane marker and on `duplicate session: board`. After the membership check and targeted retry, the scratch tests passed.

Focused commands cover config validation, SessionTmux, Sessions and SessionWaiting. Two intermediate runs hit a scratch-directory teardown race. The receiver wrote an empty `received` file after EOF during server shutdown. It now exits on EOF and each launch has its own readiness file; the tests wait for every receiver before teardown. The fixture also uses UUID sockets and `/bin/sh`.

One full run also failed the existing `relaunch from ended leaves the readable shell open` test because its windows were still present after reconcile. That test passed immediately in isolation and alongside the routing tests with the same seed, without a production change. The final gate reruns that seed.

## Scratch tmux evidence

The routing tests start private `-L` servers under `/tmp`, use a receiver executable instead of Claude, and stop their servers afterward. The following transcripts are copied from the passing full-suite run. The tests regenerate `tmp/session-routing-false.txt` and `tmp/session-routing-true.txt`.

### Unset mode

```text
Scratch socket: fm-routing-21ae5b28-2c60-4903-a201-bb39c01b1742
alpha|x-1.2
beta|x-1.2
coordinator|coordinator
alpha|draft:arrangement
Windows: @0, @1, @2; draft: @3
Coordinator pane: %0; build pane: %3
Continue received by alpha only; beta received nothing.
Focus refused beta access to alpha's build pane.
Open session selected the marked pane with a client attached.
Foreign pane marker refused by Open session and Continue.
Attach: tmux -L 'fm-routing-21ae5b28-2c60-4903-a201-bb39c01b1742' attach -t 'alpha:@0'
```

### Shared mode

```text
Scratch socket: fm-routing-8924be16-9251-4d4e-ba14-e217a6768619
board|alpha/x-1.2
board|beta/x-1.2
board|__foreman__/coordinator
board|alpha/draft:arrangement
Windows: @0, @1, @2; draft: @3
Coordinator pane: %0; build pane: %3
Continue received by alpha only; beta received nothing.
Focus refused beta access to alpha's build pane.
Open session selected the marked pane with a client attached.
Foreign pane marker refused by Open session and Continue.
Attach: tmux -L 'fm-routing-8924be16-9251-4d4e-ba14-e217a6768619' attach -t 'board:@0'
```

The concurrent-launch test holds two real tmux invocations just before new-session, releases both, and requires both launches to succeed with distinct project-qualified windows. The pane-Focus checks also assert the actual selected window and pane.

## Sequential review against c9d59f6

The base is `c9d59f6b809804b435762fc0764f05f51a39f303`. HEAD has no commits beyond it, so the review covers the working-tree diff and the new routing test explicitly. No subagents were used.

### Standards

One Important finding was fixed. Routing helpers queried RuntimeState repeatedly inside window and pane enumeration. The lookup now captures the setting once and passes it through the adapter helpers (`lib/foreman/session_tmux.ex:99`, `:434`, `:457`). No new lifecycle states or transitions bypass SessionMachine.

Declined to judge the unchanged shell-wrapper design and existing polling helpers. Final verdict: Ready. No open findings.

### Spec

One Important coverage gap was fixed. Recovery tests alone did not exercise initial board launches. `test/foreman/sessions_test.exs:280` now launches planning, epic and singleton conversations through Sessions in shared mode. The nearby recovery test covers persisted UUIDs, response-loss recovery, reuse and relaunch. A Minor wording inconsistency about epic window names was corrected in `docs/coordinator.md`.

Each Must hold path is covered by routing or existing regression tests: launch, reuse, relaunch, observe, Continue, waiting targets, build Focus, attach text and the singleton coordinator. Draft names and repeated ticket IDs across projects are included.

Declined to judge moving existing windows after a configuration change. That behavior was not requested and is documented as unsupported. Final verdict: Ready. No open findings.

### Risk

Two Important findings were fixed:

- Concurrent first launches could both choose new-session. The retry in `lib/foreman/session_tmux.ex:519` handles only the duplicate-session response.
- A foreign `@foreman-pane` marker could send input to another conversation. `pane_in_window/3` at `lib/foreman/session_tmux.ex:291` now checks membership before input or client switching.

The safety fact reached proof level 4: real scratch tmux tests require project ownership for Focus, conversation identity for window resolution, and window membership for input panes. They verify that beta receives no input when alpha continues, including after alpha's pane marker is changed to beta's pane. Existing default-mode, coordinator integration and child-environment tests also pass in the full gate.

Declined to judge an operator moving panes between verification and input; that cross-command adversarial race is outside this change. The cheapest repeat check is `mix test test/foreman/session_tmux_routing_test.exs`. Final verdict: Ready. No open findings.

## Final verification

`mix precommit --seed 835292` exited 0 with no warnings. Progress dots are omitted below.

```text
Repository hygiene: no license material or operator paths detected
Running ExUnit with seed: 835292, max_cases: 16
Generated escript foreman with MIX_ENV=test
Finished in 130.1 seconds (10.9s async, 119.1s sync)
5 properties, 839 tests, 0 failures
GATE_EXIT=0
```

`foreman check` returned `tickets valid`. `git diff --check` passed. The reference diff is absent. No Critical or Important review findings remain open.

## Open items and boundaries

No implementation gaps or new tickets to file. The coordinator owns ticket closure; `fm-c2w.32` remains in progress.

No commits, pushes, deploys or release installs were performed. Tests used the checkout-specific SQL sandbox database. There was no direct live-database access or live-tmux operation. Only the requested progress/report telemetry used the board CLI. User configuration and skills files were unchanged. No browser verification was needed because no UI files changed.
