---
id: fm-c2w.21
title: "Epic page: stage history facts render as scattered, misaligned key/value blocks"
type: bug
status: closed
priority: 2
parent: fm-c2w
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-19
closed: 2026-10-24
close_reason: "History cards with aligned label/value pairs merged (1d76344); screenshots light/dark at 1440/390 inspected; 840 tests green on rerun. Live check after next deploy."
---

On the epic page (e.g. fm-3c3 at 1440px), EPIC STAGE HISTORY lays each event's facts (Title, Session, Spec, Epic) out with labels on one line and values floated far right/below with large empty gaps, and columns of uneven width with stray rules underneath. Seen in docs/acceptance/fm-epic-coord/epic-1440-light.png. Pre-existing, not from fm-3c3.8.

Acceptance: each history event reads as a compact card or row with label/value pairs aligned (label column, value beside it), no large blank gaps, consistent widths; screenshots light/dark at 1440 and 390 inspected; mix precommit green.
