---
id: fm-zpn
title: "Answers nobody picks up reach the coordinator"
type: feature
status: in_progress
priority: 1
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

## What to build
A request answered after its session stopped waiting reaches no one. fm-zgd.7 (2026-10-19): the build asked a decision, waited twice, reported and stopped; the user answered 15 hours later and nothing consumed the answer or told the coordinator.

When a request becomes answered and no live wait holds it (the asking session is reported, exited or gone, or its last wait timed out with no later wait), the board marks it 'answer not picked up': it stays in Needs you under its own heading with the answer shown, and the notification path tells the coordinator which session and ticket it belongs to. A later wait on the request clears the mark. The rule is a guarded transition on the request lifecycle machine, not a side check.

## Acceptance
- [ ] Machine tests: answered with a live wait → consumed as today; answered with no live wait → not_picked_up; a later wait clears it
- [ ] Needs you shows not-picked-up answers with ticket, session and answer; LiveView test
- [ ] A notification fires once per such answer
- [ ] Reproduce fm-zgd.7's shape end to end: ask, wait times out, session reports, answer arrives; the mark and notification appear
