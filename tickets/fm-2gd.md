---
id: fm-2gd
title: "Test suite: isolate temp dirs and tmux sockets across concurrent runs"
type: task
status: open
priority: 3
parent: null
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: null
close_reason: null
---

Two concurrent mix test runs in sibling worktrees collided on a shared temporary-directory cleanup and a shared tmux socket name (fm-age report, 2026-10-21); TMPDIR per run avoided it. Make fixture dirs and test tmux socket names unique per test VM so parallel worktree gates never interfere, without relying on the caller's TMPDIR.

## Acceptance
- [ ] Two mix precommit runs started together in sibling worktrees both pass, three times in a row
- [ ] No test depends on the caller setting TMPDIR

## Notes
- 2026-10-21 user: 2026-10-21: initiatives_live_test.exs failed 2 of 7 runs in the fm-parked worktree with no code change between runs (TMPDIR isolated), so the flake is not only shared temp dirs; include the LiveView signing/clock failure in this ticket's scope.
