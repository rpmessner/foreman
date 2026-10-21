---
id: fm-dhv
title: "Wait lease receipts: bound their write volume"
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

fm-zpn's waits append a lease receipt to request_events on every CLI poll (about every 2 s), so a 2-hour wait writes about 3600 rows per waiter. Measure the growth on the live board after a week, then either renew in place, compact receipts once a request is collected, or index for the liveness query. No schema change without asking.

## Acceptance
- [ ] Row counts per collected request measured on the live board
- [ ] Chosen bound implemented; liveness and pickup tests still green
