# Coordinator session

Run `foreman coordinator` in the coordinator pane on the board's tmux server. The web service must be available and authenticated CLI configuration must already work.

- No recorded conversation: launch Claude with a new `--session-id`.
- Recorded conversation: launch with `--resume`.
- `foreman coordinator --fresh`: replace the recorded conversation.
- `foreman coordinator --adopt <uuid>`: record an existing conversation without launching it. This command does not need tmux.

Stop the running coordinator before replacing or adopting its conversation. The board's Focus control selects its window; Relaunch resumes it; Start fresh requires confirmation.

The service replaces only the requesting pane, after checking its socket and its `coordinator` tmux session. Claude runs in `~/dev/music`, with `/orient` as the only prompt and the existing per-launch hooks. The service PATH must contain `claude`. No global Claude settings change.

Pane startup uses the tmux server/session environment, not the web service's client environment. The wrapper starts `$SHELL` as an interactive login shell, removes service settings before Claude, and returns to `$SHELL` when Claude exits. Per-launch hooks carry their URL and token explicitly and resolve `foreman` on the pane PATH. Coordinator respawns disable automatic renaming before replacing the pane, preserving the layout's window name.

The singleton uses the reserved system key `__foreman__/coordinator` in the existing session table. It has no ticket overlay or configured project. Only session-waiting requests use that system subject; ordinary approvals still need tickets. Idle time never parks this session. A missing window becomes `ended`, preserving its conversation ID.

## Epic coordinators

Launch a ticketed epic from its board row or epic page. The coordinator runs in the project's main checkout, in a window named by the epic ID. It owns only that epic and uses the dispatch skill's `pi-window --pane` mode. Build panes inherit the coordinator's tmux server and project session; `FOREMAN_SESSION` remains the logical build name.

Building tickets expose Focus in their ticket sheet. Dispatch's `window` field holds the stable `%pane-id`; Focus selects both its containing window and that pane. Ended or parked epic conversations use the existing Relaunch and idle-parking lifecycle. The singleton main coordinator is unchanged.

The launch wrapper records its coordinator pane in the window's `@foreman-pane` option. Continue uses that identity rather than the active pane, which may be a build. Older windows without the option can Continue only when they contain one pane; ambiguous multi-pane windows fail closed.

## Verification notes

`FOREMAN_HOST_ACCEPTANCE=1 mix test test/foreman/pane_environment_test.exs` checks the real login environment on a clean foreground scratch server. Without that flag, the test uses a fixture shell and tools. Both use stub Claude and a local ticket fixture.

`test/foreman/coordinator_integration_test.exs` runs the built escript against an isolated HTTP endpoint and scratch tmux server, with a stub Claude executable. It verifies argv, working directory, identity persistence, Focus/Relaunch, Needs you and Continue. No real Claude account is used.

Tmux takes pane PATH from the connecting client even when its global environment is clean. The adapter clears the client environment and uses `new-session -E` to keep that empty client from masking server values such as `SSH_AUTH_SOCK` and `DISPLAY`. It forces UTF-8 (`-u`); without a UTF-8 client locale, tmux 3.4 replaces tabs in formatted output with underscores. Shell startup files can reintroduce service settings, so the wrapper removes them after startup as well.

Tmux distinguishes socket names (`-L`) from socket paths (`-S`). The CLI's `TMUX` variable contains the latter. A new-window target needs the trailing colon (`=coordinator:`) when session and window names coincide; otherwise tmux can interpret it as occupied window zero.
