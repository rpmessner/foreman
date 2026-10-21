# fm-parked build report

Ticket `fm-c2w.33`. Review base `e6050831717268a33984d8ec14ea936e71905452` is HEAD. This report covers the working-tree diff and new files. No commits, pushes, deploys, release installs, ticket edits, or preview cleanup performed. The coordinator owns ticket closure and the post-deploy live check.

## Changed

Ticket status is `on_hold`, labelled **On hold**. Planning sessions retain `parked`. The names distinguish a deliberate ticket decision from an idle conversation whose window is gone. No existing planning-session text changed.

- `TicketStatusMachine` declares the state and transitions. Its generated document now has a golden test.
- `foreman new` and `update --status on_hold --reason "..."` require a nonblank reason. Invalid input exits 2 without changing files. Other ticket edits preserve the hold facts. Leaving hold clears them.
- Ticket files store `on_hold_reason` and the ISO date `on_hold_since`. Repeating hold preserves the original date but requires a fresh reason. Handwritten held files require the reason, not the date. The reader carries both facts into the projection. The app never writes ticket files.
- Initiatives has a collapsed, project-grouped **On hold** section with badges, reason, containing epic, and shared human time formatting. Priority remains the first ordering key, then oldest hold date and stable identity. Held children retain epic membership. Parentless held tickets leave Standalone work and Unplanned.
- Held tickets never qualify as stale, including old dispatched or building sessions. URL filters, configured views, and the default Open view recognize the status.
- The sheet shows the reason and hold date. Epic-board badges use the same label. Held epics link to their board rather than an unsupported ticket sheet. Session target lookup includes the new section.
- Mobile ticket metadata spans both grid columns so the added badge does not squeeze the status text.

## Machine rows

All rows have no effects, consistent with the existing file-status machine. The CLI executes the selected transition through `step/3`, then validates and publishes the file facts.

| From | Event | To |
| --- | --- | --- |
| any, including on_hold | hold | on_hold |
| on_hold | reopen | open |
| on_hold | start | in_progress |
| on_hold | close | closed |
| on_hold | defer | deferred |

Existing reopen, start, close, and defer transitions from every other state remain unchanged. The full matrix is `docs/machines/ticket_status_machine.md`.

## Test evidence

Failing-first checks used `TMPDIR=/tmp/fm-parked-tests mix test` at the requested seams:

| Seam | Observed initial failure |
| --- | --- |
| Status machine | `:on_hold` absent from declared states |
| CLI refusal | Returned invalid status instead of a reason error |
| File round trip | Rejected the two new frontmatter keys |
| File reader | Dropped the stored reason |
| Initiatives grouping | New section returned no held tickets |
| Sheet and badge | Status did not render as On hold |
| Section context | Missing containing-epic element |
| Held epic navigation | Link targeted the sheet, then board badges exposed `on_hold` |

Each passed after its implementation slice. No placeholder functions or subagents were used.

Risk-focused command:

```text
TMPDIR=/tmp/fm-parked-tests mix test test/foreman/ticket_cli_test.exs test/foreman/ticket_file_test.exs test/foreman/ticket_files_test.exs test/foreman_web/live/initiatives_live_test.exs test/foreman/drilldown_test.exs test/foreman/sessions_test.exs
1 property, 106 tests, 0 failures
```

A mutation removing the stale exclusion exposed a weak fixture: dispatch had created fresh sessions. After aging those sessions, the mutation failed with `stale: true`; restored production code passed. The final suite includes that stronger fixture and verifies the empty Stale view.

A probe loaded the baseline codec under a temporary module name and passed current output through it:

```text
Legacy byte identity and resumed parsing: PASS; old CLI rejects held files as documented
```

Evidence is `docs/acceptance/fm-parked/format-risk.txt`. New CLI tests also verify hold facts disappear physically from resumed files and `check` accepts every departure status. `foreman check` on this checkout returned `tickets valid`.

One intermediate focused run hit the documented transient LiveView signing failure. `mix test --failed` passed on rerun. The first precommit attempt stopped on formatting; formatting was applied only to changed files. A later full run failed `SessionsTest`'s existing "relaunch from ended leaves the readable shell open" assertion because an unexpected tmux window remained. The isolated test and the following full precommit passed without code changes. Its root cause was not established. None of these failures remains in the final gate.

## Owned preview and browser evidence

`FOREMAN_SESSION=fm-parked devserve up` returned `http://127.0.0.1:4881`. `devserve ls --json` confirmed this worktree, branch and owner `fm-parked`, with running state.

| Fact | Value |
| --- | --- |
| Unit | `devserve-foreman-fm_parked-5fff04524c0a.service` |
| URL | `http://127.0.0.1:4881` |
| Database | `foreman_preview_fm_parked_5fff04524c0a` |

Reproducer:

```sh
NODE_PATH=/tmp/bb-filters-browser/node_modules node tools/hold-acceptance.cjs
```

Exit 0. The script checks preview ownership before seeding synthetic fixtures through `tools/hold-preview.exs`. The helper connects only to this preview database, starts no web server, and launches no external sessions. It inserts an already-parked planning session and ages a dispatched session to exercise stale exclusion.

All four combinations passed at 1440px and 390px, light and dark. Browser assertions cover section order, retained epic membership, reason, human date with full-time hover, distinct planning state, stale exclusion, no page overflow, and no JavaScript errors. API reads returned the expected 401 because the preview has no token setting. Authenticated preview API success was not exercised.

Eight inspected screenshots and `browser.json` are in `docs/acceptance/fm-parked/`. The first capture caught the sheet mid-transition; the script now waits for its animations. Final captures show readable badges, wrapped reasons, and aligned mobile metadata. Existing mobile epic columns remain horizontally scrollable. The preview remains running for coordinator cleanup.

## Sequential self-review

No subagents. The three-dot committed diff is empty because no commits were made; review included the requested uncommitted diff against the fixed base and every new deliverable. Axes ran in order, then changed hunks were rechecked.

### Standards

Read AGENTS, CODING_STANDARDS, formatter configuration, and the house baseline. Ticket state uses the declared FSM and its executor. Section disclosure reuses `Disclosure`; grouping is a pure projection. New UI uses streams, shared icons and times, and label-only badges. No Critical or Important findings remain. Minor mobile metadata squeezing was fixed after screenshot inspection.

Declined: unrelated existing sidebar and horizontally scrollable epic-column layout. Verdict: Ready.

### Spec

Checked every `fm-c2w.33` acceptance item against the machine, CLI, codec, grouping, stale filter, sheet, docs, and scrub. Important fixed: held epics initially linked to an unsupported sheet; a failing test now covers board navigation and human-readable board badges. All requested implementation checks pass. No Critical or Important findings remain.

Declined: the post-deploy live check belongs to coordinator close-out. Verdict: Ready for close-out.

### Risk

The safety fact is that this adds file-owned facts and a separate display collection without removing held children from the epic tree or changing overlay stages. The codec probe and 106-test focused run prove unchanged-file compatibility, resumed-file compatibility, preserved drilldown totals, and session target reachability. Proof level 4 for these boundaries, level 5 for the owned browser flow.

Important fixed: stale tests originally used fresh sessions and could pass without the exclusion. The aged fixture now fails under that mutation. No Critical or Important findings remain.

Compatibility limit: an old CLI or old `foreman check` refuses a checkout containing held files. `docs/specs/ticket-files.md` records the upgrade requirement. Unheld files keep their old canonical bytes; leaving hold removes the new keys. This is an intentional format extension, not silent backwards compatibility.

Declined: production rollout and load profiling. Cheapest close-out checks are the focused command above, the browser reproducer, and `mix precommit`. Verdict: Ready with the documented reader-upgrade requirement.

## Scrub and final gate

Both commands used the external pattern file supplied in the brief. `SCRUB_PATTERN` below denotes that same read-only file; its contents were not copied.

```sh
git diff e6050831717268a33984d8ec14ea936e71905452 | grep -i -E -f "$SCRUB_PATTERN"
# output: empty; grep exit 1

git ls-files --others --exclude-standard -z | xargs -0 -r grep -i -E -f "$SCRUB_PATTERN"
# output: empty; xargs exit 123 because grep returned 1
```

The scans include new files and the coordinator-owned brief. No reference ticket files, commit messages, author metadata, or identifying work text were imported.

Final gate output is `docs/acceptance/fm-parked/precommit.txt`:

```text
TMPDIR=/tmp/fm-parked-tests mix precommit
Repository hygiene: no license material or operator paths detected
5 properties, 819 tests, 0 failures
precommit exit: 0
```

Zero warnings. `git diff --check` passed. No live service, live database, existing tmux session, user configuration, or sibling worktree was changed. Progress and report telemetry are the only board writes.

## Proposed follow-ups

- Revisit the test-socket isolation follow-up already reported by fm-age. The tmux-window failure above recurred during this build; no test infrastructure was changed here.
- Coordinator close-out must upgrade the CLI/check readers before creating held files, perform the post-deploy live check, and clean up this preview. Authenticated preview API checks remain unavailable until the owning preview workflow supplies authentication.
