---
id: fm-c2w.30
title: "Port: ticket priority on the board, overrides and Jump to front"
type: feature
status: closed
priority: 2
parent: fm-c2w
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: 2026-10-24
close_reason: "Priority badges, sheet Priority select and Jump to front visible on the live board; live on release 20261024T191409 (deployed 2026-10-24 with mix foreman.deploy; smoke passed)."
---

## What to build
Port of work fork commit 5c5b6a1, re-implemented and re-committed here (no work content, personal identity). P0-P4 badges on rows, cards and the ticket sheet. A board edit is a Postgres override declared as a machine and cleared when the ticket file catches up. Ready lists, Initiatives and Needs you sort by effective priority. 'Jump to front' is exposed through `foreman ls --overlay`. Includes a migration (ask-first: approved by the user 2026-10-21 as part of this port).

Follow-up in the skills repo after this lands: orient and dispatch honour overrides and jumps.

## Acceptance
- [ ] Override machine with table, pure step and generated doc
- [ ] Sorting by effective priority on Ready, Initiatives and Needs you
- [ ] ls --overlay shows overrides and the jump
- [ ] Work-string scrub of the diff and authors clean; mix precommit green; live check after deploy
