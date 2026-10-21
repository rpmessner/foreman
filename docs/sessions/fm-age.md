# fm-age build report

Ticket: `fm-c2w.31`. Review base: `bb63971ecc2fc25d10c73000857c45516f3d9d86`.

## Changed

- `lib/foreman/initiatives.ex` parses creation timestamps, including date-only values. Parentless tickets sort newest first, with unknown dates last and stable ID ties.
- Unplanned contains only untouched, open parentless tickets. Stages beyond queued, past transitions, sessions including ended sessions, planning conversations, and requests move tickets to Standalone work. Ticket status alone does not imply board activity.
- Closed parentless tickets are excluded, matching the reference. In flight includes Standalone work before dispatch and after review. Other filters still apply.
- `lib/foreman_web/live/initiatives_live.ex` renders both collapsed, project-grouped sections through streams. Ticket ages reuse `TicketDetail.timestamp` and `RelativeTime`, with full timestamps on hover.
- `lib/foreman/sessions.ex` searches both parentless groups so existing session targets remain reachable.
- LiveView tests cover grouping, historical activity, ended planning conversations, ordering, unknown dates, age rendering, and expanded-epic ticket ages.

No commits, pushes, deploys, release installs, ticket edits, or preview cleanup performed.

## Evidence

Failing-first tests used the existing `Initiatives.snapshot/1` and LiveView seams. Grouping initially returned all four tickets in Unplanned instead of only `untouched`. Ordering initially returned alphabetical IDs instead of newest first. After ordering passed, the age assertion failed because no timestamp rendered. The In flight test initially returned an empty Standalone list. Each passed after its implementation slice.

A mutation dropping planning-session activity failed the ended-conversation test on its orphan assertion. The implementation was restored.

Final focused command:

```text
TMPDIR=/tmp/fm-age-tests mix test test/foreman_web/live/initiatives_live_test.exs test/foreman/initiatives_tree_test.exs test/foreman/sessions_test.exs
64 tests, 0 failures
```

Browser command:

```text
PREVIEW_URL=http://127.0.0.1:4881 NODE_PATH=/tmp/bb-filters-browser/node_modules node tools/age-acceptance.cjs
browser exit: 0
```

The owned preview uses synthetic `age-demo` fixtures. Browser assertions verify planned and standalone ages, Unplanned order, full-time hover attributes, ticket-sheet navigation, no page overflow, and no JavaScript errors.

Screenshots inspected at 1440px and 390px, light and dark. Ages remain readable, stage badges align, and mobile rows wrap without clipping. Artifacts are in `docs/acceptance/fm-age/`, including four `initiatives-<width>-<theme>.png` files and `browser.json`.

`devserve ls --json` confirmed this worktree, branch `fm-age`, owner `fm-age`, and state `running`:

- Unit: `devserve-foreman-fm_age-08dc71f39241.service`
- URL: `http://127.0.0.1:4881`
- Database: `foreman_preview_fm_age_08dc71f39241`

The preview remains running for coordinator close-out. Authenticated API behavior was not exercised. GET `/api/repos` and `/api/tickets/age-demo/age-new` returned the expected 401 because the preview has no API token setting. No API writes attempted.

## Sequential review

### Standards

No Critical or Important findings. Section disclosure still uses the declared `Foreman.Initiatives.Disclosure` FSM. Grouping is a computed projection, not a new lifecycle. Streams, HEEx, icons, and shared time formatting follow project standards. Re-review after fixes passed. Unrelated existing UI was outside scope.

### Spec

Two Important coverage gaps were found and fixed: ended planning conversations and ages inside expanded epics. Both now have LiveView coverage. No remaining Critical or Important findings. Epic and draft container ages were excluded because the reference adds ages only to ticket rows.

### Risk

Tree membership, totals, and stage derivation are unchanged. `Sessions.target` searches both collections, verified directly by regression tests. Three repo-scoped activity queries are added per snapshot; planning-session keys reuse the existing query result. Focused tests and browser checks passed. No remaining Critical or Important findings. Production load profiling was not performed.

## Final gate

```text
TMPDIR=/tmp/fm-age-tests mix precommit
Repository hygiene: no license material or operator paths detected
Finished in 91.1 seconds (4.3s async, 86.7s sync)
5 properties, 751 tests, 0 failures
precommit exit: 0
```

Zero warnings. Full output: `docs/acceptance/fm-age/precommit.txt`.

The required `git diff` against the review base piped through the brief's case-insensitive forbidden-string grep printed nothing. Grep exit was 1, meaning no matches. `git diff --check` also passed.

## Proposed follow-ups

- Isolate test fixture directory and tmux socket names across concurrent test VMs. The first full gate encountered a shared temporary-directory cleanup collision and an unrelated LiveView token failure. A diagnostic attempt using `TMUX_TMPDIR` failed because the app's sanitized tmux environment did not share that socket directory. Using only an isolated `TMPDIR` produced two green full gates. No test infrastructure changes were made here.

The coordinator owns ticket closure and preview cleanup.
