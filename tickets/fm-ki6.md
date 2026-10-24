---
id: fm-ki6
title: "One deploy command for the live board"
type: task
status: closed
priority: 2
parent: null
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: 2026-10-24
close_reason: "Used for the real deploy; live on release 20261024T191409 (deployed 2026-10-24 with mix foreman.deploy; smoke passed)."
---

## What to build
Deploying is a seven-step manual recipe (prod compile, assets.deploy, release --overwrite, copy into a timestamped releases dir, stop worker and web, switch the current link, start, rebuild and install the CLI escript). Make it one script in the repo: refuses a dirty tree or a non-main branch without a flag, builds, installs under a new release id, switches current, restarts web and worker only (never the tmux service: it hosts live sessions), runs the existing release smoke against the new release, rolls current back to the previous release when the smoke fails, then installs the CLI. Prints the release id and the smoke result.

## Acceptance
- [ ] Script plus a README section replacing the manual steps
- [ ] A failing smoke (forced in a test or dry run) leaves the previous release current and services running
- [ ] The foreman-tmux service is never stopped (asserted in the script's test)
- [ ] Used for the next real deploy; the live board serves the new release
