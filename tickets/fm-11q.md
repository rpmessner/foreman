---
id: fm-11q
title: "Ticket sheet: rename 'Beads fields', human time for created at"
type: bug
status: in_progress
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

The ticket sheet's Overview still has a 'BEADS FIELDS' heading (tickets are files now) and shows created at as a raw ISO string (2026-10-20T10:00:00Z), against the house rule that times use the shared human format with the full time on hover. Seen in fm-c2w.30's screenshots.

## Acceptance
- [ ] Heading names the ticket file fields
- [ ] Times on the sheet use the shared formatter with full time on hover
- [ ] LiveView test; screenshot light/dark

## Notes
- 2026-10-21 user: Follow-up seen at close-out: the Initiatives advanced filters still label the status select 'Beads status'.
