# fm-c2w.21 build report

## Changes

Epic history uses one equal-width card per event instead of intrinsic-width wrapping columns. Facts use grouped definition-list pairs with an 80px label column, a 12px gap, and a wrapping value column. History-only typography is 12px with a 20px line height. Ticket sheets keep their existing row borders and share the improved fact layout.

## Standards review

Reviewed the uncommitted diff against `87e657f02c0b14e6d7186fbc2df0118d19ec73f5`. HEAD is the base, so the three-dot committed diff is empty; the requested build changes are entirely in `git diff 87e657f`.

Checked AGENTS.md, CODING_STANDARDS.md, .formatter.exs, and the review baseline. No findings. Stream child IDs remain on articles. Definition-list groups use valid div wrappers, and no state or transitions changed. Existing Markdown rendering and relative timestamps remain intact.

Declined to judge: none. Verdict: Ready.

## Spec review

Checked fm-c2w.21 acceptance against the diff and all eight screenshots. No findings. Event name and transition precede actor and age, then ordered label/value pairs. Every epic card has the same width. Long titles and paths wrap within the value column at 390px. Enclosing card borders replace the disconnected bottom rules. All four before/after theme and width combinations were inspected.

Declined to judge: the existing mobile navigation height and horizontally scrolling ticket board, which this ticket does not change. Verdict: Ready.

## Risk review

No findings. The shared `history_row/1` also renders ticket-sheet history, so the pair grouping and typography affect both callers. Only the epic caller overrides the outer border and padding.

The safety fact is that the streamed article remains the direct child with its existing ID, while payload rendering, document links, timestamps, and refusal badges keep their existing behavior. The 53-test LiveView file exercises those behaviors, including history refresh with a sheet open. Browser checks also found five document links in the shared ticket history at 390px. Proof levels 4 and 5.

The browser geometry check passed in both themes at both widths. All five cards measured 1144px at desktop and 350px at mobile. All nine fact pairs shared the same value-column origin, had a 12px label/value gap, and aligned at the top. History scroll width equaled client width in every case.

Declined to judge: external document availability, which the renderer and this change do not control. Verdict: Ready. The cheapest repeat check is the focused LiveView file plus the four browser states below.

Review summary: Standards 0 findings, Spec 0 findings, Risk 0 findings. No Critical or Important findings remain.

## Screenshots

All eight screenshots were opened and inspected. The preview copy of fm-3c3 includes a long title, a long nested spec path, and Title/Session/Spec/Epic facts on its create event. Other events cover fewer facts and an empty payload.

| View | Before | After |
| --- | --- | --- |
| 1440 light | [Before](../acceptance/fm-history/before-1440-light.png) | [After](../acceptance/fm-history/after-1440-light.png) |
| 1440 dark | [Before](../acceptance/fm-history/before-1440-dark.png) | [After](../acceptance/fm-history/after-1440-dark.png) |
| 390 light | [Before](../acceptance/fm-history/before-390-light.png) | [After](../acceptance/fm-history/after-390-light.png) |
| 390 dark | [Before](../acceptance/fm-history/before-390-dark.png) | [After](../acceptance/fm-history/after-390-dark.png) |

The [ticket-sheet screenshot](../acceptance/fm-history/ticket-sheet-390-light.png) was also inspected. Long shared-history values wrap within their value column. The [browser check output](../acceptance/fm-history/browser-checks.txt) records the geometry assertions.

## Verification

- RED: `mix test test/foreman_web/live/initiatives_live_test.exs:638` failed at the first grouped pair's `dt:first-child` assertion because the old markup had no pair wrapper. One test, one failure. Removing the grouping restores this failure.
- GREEN: `mix test test/foreman_web/live/initiatives_live_test.exs` passed all 53 tests. The new test checks ordered Title/Session/Spec/Epic pairs, their event container, document navigation, timestamps, and omission of empty definition lists.
- Browser assertions passed for equal-width cards, aligned pairs, and no history overflow at 1440 and 390 in light and dark themes. Shared ticket-history document links remain present.
- `foreman check` returned `tickets valid`.
- `git diff --check` passed.
- `mix precommit` exited 0 with zero warnings. Complete [gate output](../acceptance/fm-history/precommit.txt):

```text
Repository hygiene: no license material or operator paths detected
Running ExUnit with seed: 620652, max_cases: 16
Generated escript foreman with MIX_ENV=test
Finished in 116.2 seconds (7.2s async, 108.9s sync)
5 properties, 840 tests, 0 failures
```

No acceptance gaps or new work to file. No commits, pushes, deploys, or release installs were performed. The ticket remains in progress for coordinator close-out.

## Preview handoff

`devserve ls --json` confirms owner `fm-history`, branch `fm-history`, state `running`, and URL `http://127.0.0.1:4880`. Unit: `devserve-foreman-fm_history-49dd6954c5ba.service`. Database: `foreman_preview_fm_history_49dd6954c5ba`.

Initial setup failed because this fresh worktree lacked dependencies. `mix deps.get` followed by a clean preview restart resolved it. Only the owned preview database was seeded. The preview remains running for coordinator inspection and cleanup. The live service and database were not changed.
