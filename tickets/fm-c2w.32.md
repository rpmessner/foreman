---
id: fm-c2w.32
title: "Port: board.tmux_session puts launched sessions in one tmux session"
type: feature
status: in_progress
priority: 3
parent: fm-c2w
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: null
close_reason: null
---

## What to build
Port of work fork commit e005d71, re-committed here. Optional `board.tmux_session` in foreman.toml: launched planning sessions open as windows of that one tmux session instead of one session per project. Unset keeps today's behaviour.

## Acceptance
- [ ] Config schema accepts and validates it; unset is unchanged behaviour (test)
- [ ] Session launch test covers the one-session mode
- [ ] Work-string scrub clean; mix precommit green
