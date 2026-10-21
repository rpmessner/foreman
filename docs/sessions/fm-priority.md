# fm-priority build report

Ticket `fm-c2w.30`. Review base `8398058b0917defedd0c4749c0ca24509137c1e4` is HEAD. This report covers the uncommitted diff and new files. No commits, pushes, deployment, release install, ticket edits or preview cleanup performed. The coordinator owns closure and the post-deploy live check.

## Changed

- `Foreman.PriorityOverride` declares priority ownership. `Foreman.Priority` executes its effects in Postgres. The app never writes ticket files.
- Projection replacement clears an override only when the projected file priority equals it. Projection and board edits share the overlay's transaction-scoped repository lock.
- Priority sorts Initiatives, including nested epics, planned/fallout tickets, Standalone work and Unplanned. Existing age, stage and ID tie-breakers remain within priority bands. `foreman ready` orders file priorities before creation time and ID, without adding a server dependency to offline ticket commands.
- Needs you sorts effective priorities and updates existing cards without remounting their forms. The `PriorityOrder` DOM adapter preserves draft text and radio choices during LiveView patches.
- P0-P4 badges show on Initiatives rows, epic cards, request cards, request summaries and the ticket sheet. The sheet has a priority select and a queued-ticket Jump to front control. Badge text is the label only, without feature tooltips.
- `foreman ls --overlay --json` adds `priority_overrides` and `jumps`, scoped by project. Existing `items` fields and ID ordering are unchanged. Priority overrides include repo, ticket ID, priority, file priority, actor and timestamp. Jumps include repo, ticket ID, actor and UTC timestamp.

## Machine and migration

Generated documents are `docs/machines/priority_override.md` and the updated `docs/machines/stage.md`, both checked by golden tests.

| State | Event / guard | Next | Effects |
| --- | --- | --- | --- |
| file | set, matches file | file | none |
| file | set, differs | board | store override |
| board | set, matches file | file | clear override |
| board | set, differs | board | store override |
| board | synced, matches file | file | clear override |
| board | synced, differs | board | none |
| file | synced | ignored | none |

Stage adds the observed `jump` event. Queued stays queued and emits the stage effect; other states ignore it. The executor atomically sets P0 and records the event, refusing non-queued tickets. Pending jumps are newest first and move ahead of ordinary tickets in the same priority band. A dispatch consumes the jump; revive cannot resurrect it.

`20261021071935_add_priority_overrides.exs` adds one table with repo key, ticket ID, priority, actor and timestamps. It has a unique repo/ticket index and a P0-P4 check constraint. No foreign key attaches durable overrides to the droppable projection. Jumps reuse `stage_events`, with no extra table. Migration rollback and reapply passed on this checkout's `foreman_test_fm-priority` database only.

## Test evidence

Failing-first commands used `TMPDIR=/tmp/fm-priority-tests mix test` with these files:

| Seam | Initial failure |
| --- | --- |
| `priority_override_test.exs` | set returned file ownership instead of board/store |
| `priority_test.exs` | set and jump returned the isolated stub's error; ordering returned the original input order |
| `ticket_cli_test.exs` | ready returned ID order instead of P0 before P4 |
| `priority_live_test.exs` | Initiatives returned a before b; Needs you returned request insertion order |
| overlay command boundary | output lacked the required override list and effective values |
| malformed sheet event | non-string priority crashed `Integer.parse` |

Stubs were separate edits under 10 lines. Additional regression coverage checks parentless priority ordering, repository isolation, missing projection rows, jump consumption after dispatch/revive and full CLI transport output. `priority_commit_test.exs` uses independent committed connections for 20 sync/edit races and a jump/dispatch race. Both tests passed. A mutation removing projection reconciliation failed because `changed_on_board` stayed true after the file caught up; restored code passed.

Focused risk verifier:

```text
TMPDIR=/tmp/fm-priority-tests mix test test/foreman/priority_test.exs test/foreman/priority_commit_test.exs test/foreman_web/live/priority_live_test.exs test/foreman/cli_transport_test.exs
20 tests, 0 failures
```

## Owned preview and browser evidence

`FOREMAN_SESSION=fm-priority devserve up` returned `http://127.0.0.1:4880`. `devserve ls --json` confirmed this worktree, branch `fm-priority`, owner `fm-priority`, and running state.

| Fact | Value |
| --- | --- |
| Unit | `devserve-foreman-fm_priority-792fee20a42a.service` |
| URL | `http://127.0.0.1:4880` |
| Database | `foreman_preview_fm_priority_792fee20a42a` |

Reproducer:

```sh
NODE_PATH=/tmp/bb-filters-browser/node_modules node tools/priority-acceptance.cjs
```

Exit 0. The script verifies ownership before connecting. Its helper starts Repo and a non-executing test-mode Oban client against that preview database only. Synthetic setup replaces preview request fixtures and config; it does not launch another server or access the live database. It is repeatable.

The browser edits P4 to P1, verifies Initiatives reorder, jumps to P0 ahead of an existing P0 ticket, and verifies Needs you reorder. The same textarea node, unfinished answer and selected radio option survive. Reading the overlay finds the override and jump; syncing the file to P0 clears the override. All four viewport/theme combinations pass with no JavaScript errors or horizontal page overflow.

Evidence is in `docs/acceptance/fm-priority/browser.json` and 16 screenshots: Initiatives, sheet, Needs you with the ticket panel, and the card list, each light/dark at 1440px and 390px. Inspected screenshots show readable badges, aligned select/button controls, wrapped mobile card metadata and no clipping in the changed controls. The first mobile layout put priority on a separate row; priority now shares the stage's grid cell.

The preview has no API token configuration. GET `/api/repos`, GET `/api/tickets/priority-demo/demo-a` and POST `/api/commands` returned 401. Authenticated HTTP CLI-to-preview success was not exercised. CLI transport tests exercise `ls --overlay` through the real endpoint in the test environment; browser interactions use real LiveView events. Domain helper reads are not claimed as authenticated API checks.

The preview remains running for coordinator cleanup.

## Sequential review

No subagents. Three-dot diff against HEAD is empty because there are no new commits; the requested self-review explicitly included all working-tree changes and new deliverables. The axes ran in order.

### Standards

Reviewed AGENTS, CODING_STANDARDS, formatter configuration and the house baseline. Ownership transitions use the declared table and effects interpreter. Jump auditing uses Stage. UI collections remain streams, icons use the shared component and badges contain only P0-P4.

Important fixed: the sheet select now uses its assigned form field. Browser checks exposed unfocused draft values being overwritten on priority refresh; the DOM adapter now preserves those controls across framework patches. Minor fixes aligned mobile badges and the select/button baseline. No remaining Critical or Important finding.

Declined: pre-existing raw fields in the ticket inspector and unrelated sidebar layout. Verdict: ready.

### Spec

Checked fm-c2w.30 against the ownership table, sync clearing, ordering, badges, jumps and overlay output.

Important fixed: the first pass called the added list `overrides` and changed `items`. The reference contract is `priority_overrides` plus `jumps`, with `items` unchanged. Corrected both, retained project scoping independently of the stage filter, and added full CLI transport coverage. Additional tests cover both recently changed parentless groups. No remaining Critical or Important implementation finding.

Declined: orient/dispatch consumer changes belong to the follow-up; the coordinator owns post-deploy verification. Authenticated preview API testing remains unavailable as stated above. Verdict: ready within those verification limits.

### Risk

The safety fact is shared transaction locking between projection, priority edits and Stage. Independent committed-connection tests prove sync cannot clear a newer board edit, and jump/dispatch cannot leave a pending jump on a dispatched ticket. This reaches proof level 4; the owned browser flow reaches level 5 for visible edits, ordering, draft preservation and sync clearing.

Important fixes made during review:

- Reconciliation establishes its own transaction even outside projection replacement.
- The card-notice path uses one pending snapshot rather than a get-then-pending race.
- Malformed priority payloads no longer crash the sheet.
- Jump queries exclude consumed events, including after revive.

Cleared risks include migration down/up, cross-repo ID collisions, stale overrides for missing projection rows, existing CLI item shape/order, age tie-breakers and request pickup lifecycle regressions. Lookups restrict IDs in SQL and filter exact repo/ticket pairs. No remaining Critical or Important finding.

Declined: production migration, endurance profiling, authenticated preview success and skills-repo consumer changes. Cheapest close-out checks are `mix precommit` and the owned-preview reproducer. Verdict: ready.

## Scrub and final gate

The exact external pattern path supplied in the brief was used for both scans. Below, `SCRUB_PATTERN` denotes that read-only file; neither its contents nor its path is copied into application code.

```sh
git diff 8398058b0917defedd0c4749c0ca24509137c1e4 | grep -i -E -f "$SCRUB_PATTERN"
# output: empty; grep exit 1

git ls-files --others --exclude-standard -z | xargs -0 -r grep -n -i -E -f "$SCRUB_PATTERN"
# output: empty; xargs exit 123 because grep returned 1 for no matches
```

Both scans printed nothing, including the coordinator-owned untracked brief. No reference ticket files, commit messages, author metadata or identifying work text were imported. There are no new commits or authors.

The first full gate found the intentionally changed CLI item shape; review restored its original contract. A later hygiene gate caught an absolute checkout path in the generated browser manifest; the manifest now records `worktree: "."` after ownership verification. Neither issue remains.

Final full output is `docs/acceptance/fm-priority/precommit.txt`:

```text
TMPDIR=/tmp/fm-priority-tests mix precommit
Repository hygiene: no license material or operator paths detected
5 properties, 797 tests, 0 failures
exit 0; zero warnings
```

`git diff --check` passed. No live service, live database, existing tmux session, user configuration or sibling-worktree launch code was changed. Only the requested progress/report telemetry targets the board.

## Proposed follow-ups

- Update orient/dispatch consumers to honor `priority_overrides` and `jumps`, as planned by fm-c2w.30. Offline ready remains file-backed; consumers combine it with the overlay rather than adding a database dependency to ticket-file reads.
- Configure preview authentication through its owning workflow, then exercise real authenticated HTTP CLI calls after merge.
- The coordinator performs the post-deploy live check and preview cleanup. No new tickets filed here.
