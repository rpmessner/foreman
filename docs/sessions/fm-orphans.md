# fm-orphans — fm-zpn

Implemented on `fm-orphans`; no commits, pushes, installs or deployments. Coordinator owns ticket closure and preview cleanup. The coordinator-owned brief is untouched.

## Changed

- `Foreman.Request` declares the guarded `not_picked_up` answer transition, pickup, wait renewal, and lost-wait observation. Repeated pickup is a guarded no-op. The generated machine document is updated.
- `Foreman.Requests.wait/3` serializes with answers using the existing per-repository transaction lock. Wait leases and pickup receipts use `request_events`; the mark uses the existing request state column. **No schema change.** Answer, note and immutable request facts survive pickup.
- CLI polls renew a lease capped at two seconds and bounded by the remaining timeout. Each CLI invocation's envelope ID identifies its waiter; one waiter timing out cannot cancel another. Abrupt process exit is detected by lease expiry, not a CLI cleanup callback. The worker's existing three-second Runtime tick submits `wait_lost` to the machine. Detection therefore normally takes at most about five seconds after the last poll, subject to worker scheduling.
- Liveness also checks accepted reports, ended dispatch sessions, and ended/parked planning sessions, by window or session UUID. A later wait collects an answer even if its original session reported.
- Needs you retains these answers under **Answer not picked up**, with ticket, session, answer and note. Its count and badge drawer include them. Pickup removes both cards and restores the ordinary answered outcome.
- Browser notifications use a separate durable `request-id:answer` ledger key, preserving the existing cross-tab Web Lock. Native notifications distinguish pending and uncollected phases. Both name the session and ticket. Existing permission/platform settings remain respected.

## Evidence

### Tests

Failing-first assertions covered the machine's orphan answer, wait persistence, agent wait consumption, retained-answer rendering, native notification, session UUID lookup, rejected reports, historical-answer protection and overlapping waiters. The initial machine failure returned `answered` instead of `not_picked_up`; the wait stub returned `{:error, :todo}`; the page lacked the retained-answer heading; the notification runner received no second-phase notification. Later fixes turned each green.

`test/foreman/request_pickup_test.exs` covers deadlines, report/exit/gone, later pickup, preserved answer/note, lease expiry after answering, historical requests, overlapping waits and the API command boundary. Machine tests cover the new rows and repeat pickup. Existing answer tests now explicitly establish a live wait where they require the previous immediate-answer behavior.

`test/foreman/request_commit_test.exs` races answer and wait ten times using independent committed connections. Both operations succeed, the final answer is retained, pickup cannot be undone by reconciliation, and at most one not-picked-up transition is recorded. Native notification tests assert one second-phase notification and none on repeat scans or pickup. The repeated-pickup guard assertion and concurrency tests are regression coverage, not claimed as failing-first evidence.

### Owned preview

Initial devserve startup failed because checkout dependencies were absent. After `mix deps.get`, retrying the same authorized `devserve up` succeeded. No replacement server or configuration changes were used.

| Fact | Value |
| --- | --- |
| Owner / branch | `fm-orphans` / `fm-orphans` |
| Worktree | this checkout |
| Unit | `devserve-foreman-fm_orphans-ab5e33565422.service` |
| URL | `http://127.0.0.1:4880` |
| Database | `foreman_preview_fm_orphans_ab5e33565422` |

`devserve ls --json` verified ownership and running state. Preview remains running for coordinator close-out.

Reproducer: `NODE_PATH=<Playwright modules> node tools/orphans-preview.cjs`. It verifies the owned preview before connecting. Its helper starts only Repo and a non-executing test-mode Oban client against the named preview database; it starts no server or runtime worker.

The flow asks a decision, ends a zero-duration wait, reports the session, answers through the browser, sees the retained section in two tabs, observes **one** answer notification across those tabs, and starts a later wait that returns `state: answered` with `Compact` and its note and removes the card. Browser Notification construction is captured rather than presenting a desktop popup. No browser errors.

- [Transcript](../acceptance/fm-orphans/transcript.json)
- [Light](../acceptance/fm-orphans/light.png) / [dark](../acceptance/fm-orphans/dark.png): inspected; ticket/session metadata fits, answer and note are distinct, borders and text remain legible.
- [Race test output](../acceptance/fm-orphans/race.txt)

**API limitation:** authenticated `POST /api/commands` returns 401 in this preview, as expected from the brief. Real HTTP CLI ask/wait/report could not be exercised there. Setup and pickup use the public application functions against the preview DB; answer submission uses the real LiveView. The authenticated command boundary and CLI tests run in the test suite. This is not a claim of a full authenticated CLI-to-preview E2E run. Native macOS delivery was tested through its runner boundary, not on macOS hardware.

## Sequential review

Fixed point: `bb63971ecc2fc25d10c73000857c45516f3d9d86` is HEAD. There are no commits after it; the explicitly requested self-review covered the working-tree diff and new deliverables. No subagents.

### Standards

Reviewed AGENTS, CODING_STANDARDS and the house baseline, then the machine, interpreter, UI and notification changes.

Important fixed: repeated pickup initially bypassed the machine in the executor. Its idempotency guard and no-op now live in the declared table. UI collections are streams; timestamps reuse the shared formatter; there are no migrations or new dependencies. No open Critical/Important finding.

Declined: unrelated pre-existing theme styling. Verdict: ready.

### Spec

Checked fm-zpn against answer-time detection, later consumption, retained answer details, one-shot notification, session liveness and timer-driven expiry.

Important fixed: planning-session liveness initially matched only the tmux window. It now also matches session UUIDs, with a red/green regression. Timer behavior is wired into Runtime, not left as a table-only implementation. Browser evidence demonstrates the requested late-answer shape, with the explicit authentication limitation above. A final UI check also found that the count included retained answers while its drawer omitted them. A failing-first LiveView test and the browser check now cover drawer retention and removal; the count's accessible label was corrected. No open implementation Critical/Important finding.

Declined: retroactive classification of pre-tracking historical answers; the ticket specifies what happens when a request becomes answered. Verdict: ready within the stated preview API limitation.

### Risk

Safety fact: answer, lease renewal, pickup and expiry resolution acquire the same existing transaction lock and re-read the request before stepping. Independent committed-connection races prove this at level 4; the preview proves visible pickup behavior at level 5.

Important fixed:

- Reconciliation initially would resurrect historical answered requests lacking pickup receipts. It now considers only tracked waits and excludes collected answers.
- A rejected report audit could invalidate a live lease. Only accepted reports reaching `reported` count.
- A short overlapping wait could cancel a longer live wait. Leases are now keyed by waiter identity; liveness checks the newest lease for each waiter.

Cleared by tests: answer/note loss during pickup, duplicate terminal notification transitions, duplicate browser notifications across two tabs, repeat pickup, stale answer/decline submissions, and answer/wait races. No open Critical/Important finding.

Declined: deployment, live-service state, native desktop permission behavior and heavy-load endurance. Verdict: ready; cheapest close-out check is `mix precommit` plus the owned-preview reproducer.

## Proposed follow-ups (not filed)

- Configure preview API authentication through the owning configuration workflow, then run real HTTP CLI ask/wait/report against devserve. Do not change the live service to accomplish this.
- If long simultaneous waits become common, measure lease-audit write volume and query cost before choosing compaction/indexing. Current polling appends lease receipts; no unapproved schema optimization was added.
- Existing dark-theme pending-card textareas appear unusually bright in the full-page check; the new retained-answer section has no inputs. Coordinate any shared theme fix separately from parallel builds.

## Final gate

[Full output](../acceptance/fm-orphans/precommit.txt):

```text
mix precommit
Repository hygiene: no license material or operator paths detected
5 properties, 762 tests, 0 failures
exit 0; no warnings
```

`git diff --check` is clean. The final gate includes CLI, request, LiveView, notification, machine-golden and concurrency tests. No direct live-database access, deployment to port 4747, tmux changes, user-configuration edits or sibling-worktree changes were made. Only the requested progress/report telemetry targets the board.
