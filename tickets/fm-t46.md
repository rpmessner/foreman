---
id: fm-t46
title: "Launched sessions start with a clean environment, not the release's"
type: bug
status: open
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
Sessions the board launches into the foreman tmux server (Launch coordinator, planning sessions, and every pi build started from them) inherit the running release's environment. Observed 2026-10-21 in the coordinator launched on 2026-10-18: PATH starts with that release's erts and bin dirs (a release two deploys old), so plain `foreman` runs the release start/daemon script instead of the CLI escript in ~/.local/bin, and FOREMAN_DATABASE_URL is set, so mix commands in a foreman worktree can reach the live database. Every coordinator command needs a PATH filter and an unset as a workaround.

Launch builds the child environment explicitly: drop the release's PATH entries, RELEASE_* and the erts variables, and FOREMAN_DATABASE_URL; keep the user's login PATH and the session facts foreman sets on purpose (FOREMAN_SESSION, FOREMAN_ACTOR, FOREMAN_URL, the token-file setting).

## Acceptance
- [ ] A unit test on the environment builder: given a release-shaped environment, the child environment has no release PATH entries, no RELEASE_*/erts variables and no FOREMAN_DATABASE_URL, and keeps the intended FOREMAN_* facts
- [ ] Live: after deploy, Launch a coordinator; in its shell `command -v foreman` is ~/.local/bin/foreman and `env | grep -c FOREMAN_DATABASE_URL` is 0
- [ ] A pi build started from that coordinator shows the same
