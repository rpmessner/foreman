---
id: fm-c2w.31
title: "Port: ticket age on Initiatives; Unplanned holds only untouched tickets"
type: feature
status: open
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
Port of work fork commits 62d3a7f and fb71b58, re-committed here. Initiatives shows each ticket's age; Unplanned sorts newest first and holds only untouched tickets, while parentless work in flight moves to a Standalone work section.

## Acceptance
- [ ] Age shown on Initiatives rows; Unplanned newest first
- [ ] Parentless tickets with board activity show under Standalone work, not Unplanned
- [ ] LiveView tests; work-string scrub clean; mix precommit green; live check
