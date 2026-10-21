---
id: fm-c2w.33
title: "Port: parked ticket status with a required reason"
type: feature
status: in_progress
priority: 3
parent: fm-c2w
blocked_by: ["fm-c2w.31"]
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: null
close_reason: null
---

## What to build
Port of work fork commit 79be572, re-committed here. A ticket status for work deliberately set aside, with a required reason: its own section on the home page, a badge, never counted as stale. Session records already use 'parked' for a planning-session state; choose a status name or labels that keep the two distinct in UI and docs.

## Acceptance
- [ ] Ticket status machine gains the state with its transitions; generated doc updated
- [ ] CLI refuses the status without a reason
- [ ] Home section and badge; excluded from stale counts (tests)
- [ ] No UI or doc text where ticket and session parking read the same; work-string scrub clean; mix precommit green

## Notes
- 2026-10-21 user: Coordinator 2026-10-21: blocker fm-c2w.31's code is merged on main (ticket stays open only for its post-deploy check), so this starts now.
