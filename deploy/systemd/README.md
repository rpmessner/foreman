# Planning session server

Install only with the user's approval. Requires tmux 3.4 (tested), Claude Code on the web service's PATH, and the normal Claude login. Keep this unit separate from the web and worker units: no PartOf, BindsTo or restart dependency.

```sh
install -d "$HOME/.config/systemd/user"
install -m 644 deploy/systemd/foreman-tmux.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now foreman-tmux.service
systemctl --user status foreman-tmux.service
tmux -L foreman list-sessions
```

Install before the first Launch. If a server already owns the `foreman` socket, inspect and preserve its sessions; do not kill it to install the unit. Schedule a manual migration when those conversations are finished. `tmux -D` keeps the server foreground and disables exit-empty, so an empty server stays available.

Launch uses `tmux -N`: the board cannot accidentally start a server inside the web service's cgroup. Restarting the web or worker leaves this independent unit and attached clients alone. Stopping **this** unit, logging out without lingering, or rebooting ends its processes. Enable user lingering separately if sessions must survive logout; do not restart this unit as part of an app deployment.

Each project gets a session on first Launch; ticket IDs name its windows. The attach command targets the project and ticket window. Launch runs the user's interactive login startup, then `Foreman.ChildEnvironment` removes release PATH entries, release/runtime variables, `FOREMAN_DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_*`. Other login settings and intended `FOREMAN_*` session facts remain. Claude uses its default model and permission mode. No global Claude configuration is written.

Install the matching CLI escript at `~/.local/bin/foreman` **before** updating the web release. Launch invokes that absolute path's internal `child-environment` command after login startup, so a release's `bin/foreman` cannot intercept it. The helper does not start the web application or contact the board. Do not run the helper directly or log its output; it emits a shell command containing the cleaned environment.

## Remove shell-global service credentials

Before starting new manual windows or pi builds, remove exports of `FOREMAN_DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_*` from shell startup files. Keep service credentials in the service's private environment file. Also remove any release PATH additions or `RELEASE_*` and runtime exports from shell startup. Preserve the normal login PATH and the intended `FOREMAN_*` session settings.

The fm-t46 investigation found a systemd-owned server with no `FOREMAN_DATABASE_URL` in either `/proc/<server-pid>/environ` or tmux's global environment. Login startup exported the variable instead. A unit `UnsetEnvironment=` cannot stop a shell from exporting it again. No unit change or server restart is needed for that cause.

After editing startup, start a new window and check without printing credentials:

```sh
command -v foreman
# Expected: ~/.local/bin/foreman, expanded to your home directory.
test "${FOREMAN_DATABASE_URL+x}" != x && printf 'database variable absent\n'
```

Existing shells retain their old environment. Do not kill the server or its conversations to clean them. Open new windows after the startup change; finish existing conversations before replacing their shells.

Prompt overrides are read from the foreman skill's `templates/session-launch/{epic,bug,feature,task}.md` under the globally linked skill directory. Placeholders: `{{ticket}}`, `{{project}}`, `{{source}}`. Install those files before Launch. Missing templates refuse launch in normal environments; only test and acceptance configuration enables the built-in fallback.

## Adapter gotcha

Tmux 3.4 can print a socket-creation error with exit status zero (for an invalid socket path). The adapter also validates that new-window output is a tmux window ID; exit status alone is not launch evidence.
