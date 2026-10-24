---
id: fm-i68
title: "Deploy runs pending migrations with the new release before switching"
type: task
status: closed
priority: 1
parent: null
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-21
closed: 2026-10-24
close_reason: "First real use shipped fm-c2w.30's migration; board serves priority overrides without error; live on release 20261024T191409 (deployed 2026-10-24 with mix foreman.deploy; smoke passed)."
---

mix foreman.deploy (fm-ki6) never migrates, and the README's manual migration asks for DATABASE_URL by hand. fm-c2w.30 adds a migration, so a deploy would start code that needs a table that does not exist yet.

Before stopping services, run the new release's migrations (`bin/foreman eval` with Ecto.Migrator, as in the README) using the database settings the services already use (the configured systemd environment file read by the deploy process without printing or logging values, or a documented FOREMAN_DEPLOY_ENV_FILE flag). A migration failure stops the deploy with the old release still current and running. Pending migrations are listed in --dry-run. Never print the URL.

## Acceptance
- [ ] Plan: build, install, migrate (new release), stop, switch, start, smoke; dry-run lists pending migrations
- [ ] Tests with stubs: migration failure leaves current and services untouched; no secret value appears in output or logs
- [ ] README's manual migration step replaced
- [ ] First use: the deploy that ships fm-c2w.30
