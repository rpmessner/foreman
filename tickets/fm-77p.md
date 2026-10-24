---
id: fm-77p
title: "Deploy: new web release can launch sessions before the matching CLI is installed"
type: bug
status: open
priority: 3
parent: null
blocked_by: []
related: []
supersedes: []
discovered_from: null
labels: []
created: 2026-10-24
closed: null
close_reason: null
---

Since fm-t46, Launch runs ~/.local/bin/foreman child-environment after login startup, so the web release depends on a CLI that has that command. Foreman.DeployLifecycle installs the CLI last (after start and smoke), and deploy_test asserts smoke < cli and no CLI install on failure. A session launched between web start and CLI install gets an old CLI without child-environment and its window fails to start. Window is seconds per deploy; first deploy after fm-t46 is the exposed one.

Decide: install the CLI before stop/switch (new CLIs stay backward compatible with the previous web; changes the 'failed release leaves CLI untouched' contract), or have the web refuse Launch until the installed CLI reports a compatible version.

Acceptance: chosen ordering on the DeployLifecycle table with a test; a launch during deploy never runs a CLI without child-environment; mix precommit green.
