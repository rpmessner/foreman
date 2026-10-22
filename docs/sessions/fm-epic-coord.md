# fm-3c3.8 epic coordinator

## Status

Ready for coordinator close-out. The user resolved prompt ownership in the resume instruction: "Ship the short execution-coordinator prompt in the app" and keep existing planning templates unchanged. This resolves the decision raised as request `98e83ae0-8aef-45fa-98d2-dc53edc75cd7`; the resumed build used that explicit instruction, not the earlier pending wait result.

After the machine restart, I preserved and reviewed the uncommitted work, refreshed scratch launch and pane Focus evidence, restarted the owned preview, repeated all eight browser checks, and reran `mix precommit`. No commits were made. The ticket stays in progress for coordinator verification and closure.

## Changed

- `Sessions.launchable?/1` accepts ticketed epics and their derived building, shipping, and shipped stages. Done and abandoned epics remain excluded. Shipped means all children are closed while the epic itself remains open.
- The app-owned opening prompt names the epic, limits ownership to it, names dispatch and foreman, and requires `pi-window --pane` in the coordinator's own window. Planning prompts and the main coordinator's launch workflow remain unchanged.
- Epic sessions reuse the existing `SessionMachine`, persistence, Focus, Relaunch, and parking paths. No new lifecycle state or database schema was needed.
- Dispatched or building pane tickets expose Focus in their ticket sheet. The server resolves the current stored `%pane-id`, verifies its project, and selects its window and pane. Window-mode builds retain their previous UI behavior.
- The wrapper records `@foreman-pane` so Continue cannot accidentally address a selected child build. Legacy single-pane windows remain supported; ambiguous unmarked multi-pane windows refuse Continue.
- Mobile epic rows keep their title, stage, Launch control, and progress visible together. Desktop columns remain unchanged. `docs/coordinator.md` records the pane identity contract.

## Evidence

- Failing-first tests covered epic eligibility, the execution prompt, pane Focus, and the ticket-sheet control. Existing parking and resume tests now run for both an unplanned ticket and a ticketed epic. UI tests cover row and epic-page Launch, Focus, Relaunch, and terminal exclusion.
- [Scratch epic launch](../acceptance/fm-epic-coord/launch-transcript.txt) records stub Claude argv and the actual opening prompt from `Sessions.launch/2`. The test verifies the project/window name and reuse of the same window and conversation.
- [Pane Focus](../acceptance/fm-epic-coord/pane-focus-transcript.txt) records the selected window and pane. The adapter test also rejects missing and foreign-project targets.
- [Actual dispatch script](../acceptance/fm-epic-coord/dispatch-transcript.txt) ran read-only `pi-window --pane` from the skills repo against a scratch server with a fixture-only pi function. It created one build pane in the coordinator window, retained coordinator focus, inherited the scratch socket, and kept `FOREMAN_SESSION=epic-build`.
- Refreshed [risk test output](../acceptance/fm-epic-coord/risk-tests.txt): 49 tests passed, including prompt, lifecycle, tmux, session-launch LiveView, coordinator integration, and waiting tests. Scratch launch and pane Focus transcripts above were regenerated from this run.
- Playwright rechecked connected LiveViews, Launch labels, control bounds, document overflow, and browser errors after the restart. All eight combinations passed with no browser errors. The repeatable [browser verifier](../acceptance/fm-epic-coord/browser-check.cjs) takes the devserve URL and requires Playwright on `NODE_PATH`. The initial 390px check failed because Launch required horizontal scrolling; it passed after the responsive-row change.
- Screenshots inspected: [board light 1440](../acceptance/fm-epic-coord/board-1440-light.png), [board dark 1440](../acceptance/fm-epic-coord/board-1440-dark.png), [board light 390](../acceptance/fm-epic-coord/board-390-light.png), [board dark 390](../acceptance/fm-epic-coord/board-390-dark.png), [epic light 1440](../acceptance/fm-epic-coord/epic-1440-light.png), [epic dark 1440](../acceptance/fm-epic-coord/epic-1440-dark.png), [epic light 390](../acceptance/fm-epic-coord/epic-390-light.png), and [epic dark 390](../acceptance/fm-epic-coord/epic-390-dark.png). Controls fit without overlapping labels. Existing epic ticket columns and the graph retain their horizontal scrolling.

## Sequential self-review against 9392b0c

### Standards

Reviewed the uncommitted diff against `9392b0c4a72f11680f30aa0bd120ab7412ae36da`, local instructions, and the house baseline. Repeated this axis after resuming. No Critical or Important implementation findings. The existing session machine owns lifecycle transitions; Focus only selects an existing target. Removed two unnecessary explanatory comments in the original build. On resume, corrected `SessionPrompt`'s module description to distinguish the app-owned execution prompt from skill-owned planning templates. Declined unrelated refactors and external skill changes. Verdict: Ready.

### Spec

Repeated this axis after Standards. The user's explicit resume decision resolves the former Important prompt-ownership issue. The implementation covers every fm-3c3.8 acceptance check. The original build fixed the initially omitted nonterminal shipped stage and the mobile control visibility gap. Refreshed screenshots show Launch on the row and epic page in both themes at both widths. Lifecycle and LiveView tests cover Focus, Relaunch, parking, and terminal exclusions. Declined real-Claude behavior and skill-repo edits, both forbidden by the brief. No open Critical or Important findings. Verdict: Ready.

### Risk

Fixed two Important findings with failing-first checks:

1. Continue used the active pane, which could be a build. It now uses the recorded coordinator pane. A separate fallback-removal mutation failed the legacy compatibility test before restoration.
2. Showing the new Focus control for window-name builds assumed those windows belonged to the project's board-server session. The control now applies only to pane dispatches, leaving main-coordinator windows unchanged.

Repeated this axis after Spec. The safety fact is that Focus resolves a stored dispatch, checks the project on the board socket, and neither sends input nor closes a window. The fresh 49-test run proves that fact at proof level 4 and checks that Continue reaches the coordinator rather than an active build pane. The first full suite also exposed nine ambiguous expansion selectors after Launch appeared; those tests now identify Expand explicitly. All 39 Initiatives tests pass.

No Critical or Important code finding remains. Declined guarantees about real accounts, atomic tmux/Postgres crash recovery, and external child-pi waiting routing. Cheapest recheck is the session, tmux, session-launch LiveView, and coordinator integration suites. Verdict: Ready.

## Follow-up for the coordinator

External pane-build waiting and Continue support is separate scope, now tracked by `fm-3c3.9`. `SessionWaiting.target/4` still uses `SessionTmux.external_target/2`, whose legacy external-socket lookup accepts window names or IDs rather than `%pane` dispatch records. This slice verifies epic-coordinator waiting and Continue plus build-pane Focus, not child-pi waiting routing. No new ticket was filed by this build.

## Preview

Started with `FOREMAN_SESSION=fm-epic-coord devserve up`. `devserve ls --json` verified:

- Owner: `fm-epic-coord`
- Worktree: `~/dev/utils/fm-epic-coord`
- Unit: `devserve-foreman-fm_epic_coord-fcf4eb459d25.service`
- URL: http://127.0.0.1:4880
- Database: `foreman_preview_fm_epic_coord_fcf4eb459d25`

The preview was restarted after the machine restart with the same owner, unit, URL, and database. The refreshed [registry evidence](../acceptance/fm-epic-coord/preview.json) confirms ownership. It remains running for coordinator close-out. Browser checks did not launch sessions; functional checks used scratch tmux only. No commits, pushes, deploys, release installs, live-server changes, user-config changes, or skills-repo edits occurred. The pre-existing dispatch brief remains untouched.

## Final gate

Fresh `mix precommit` passed with zero warnings: **5 properties, 594 tests, 0 failures**. [Full output](../acceptance/fm-epic-coord/precommit.txt). `foreman check` and `git diff --check` passed. Tests use this checkout's isolated `foreman_test_fm-epic-coord` database.

The first resumed gate stopped on repository hygiene because the refreshed preview JSON contained an absolute operator path. I replaced the home prefix with `~` in the evidence file and reran the full gate successfully. No checker was weakened.

Not verified against real Claude or pi accounts, by instruction. No acceptance item remains open. Ticket closure, preview cleanup, and any authorized commit belong to the coordinator.
