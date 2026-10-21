# Ticket files: replace beads with per-ticket files and the board CLI

Status: approved 2026-10-18. Foreman draft epic `draft:ticket-files`.

## Goal

Every repo tracks its work as one Markdown file per ticket in a `tickets/` folder, written by the `foreman` CLI (or by hand) and read by the board from the files; beads (`bd`, its Dolt store, export and hooks) is removed from all seven repos.

## Why

The user uses beads only for two things: a flat-file record of planned work in the repo, and an agent toolset. Beads' embedded Dolt store made the board's reader expensive and fragile (lock probe, process guard, a 3-second `bd export` poll costing about 37% of a core idle), and brought git friction (an always-dirty activity log, import hooks, `issues.jsonl` conflicts on every merge, store copies in worktrees) and setup traps (`bd init` auto-commits; server mode lost about 55 beads in we_go_next_dev). Success: plain files in git that both the user's machines share, agents and the user edit freely, and the board reads cheaply.

## Non-goals

- Editing ticket content in the board UI. The board stays read-only for ticket files in this project; the CLI and hand edits write them.
- Two-way sync between boards or machines. Git is the sync.
- Moving the board's own state (stages, sessions, requests, drafts) out of Postgres.
- Changing ticket ids, the approvals inbox spec, or the stage machine.
- Features of beads the house does not use: compaction, federation, Dolt remotes, assignee and claim fields, the interactions log.

## Decisions

1. **Truth lives in the repo** (user). Ticket files are the source of truth; git is history and cross-machine sync. The board's Postgres only caches them, beside its own state.
2. **Layout** (user). One flat `tickets/` folder at the repo root; one file per ticket or epic, named by id only (`tickets/fm-zgd.3.md`). Hierarchy, status and dependencies live in frontmatter. Closed tickets stay in place with `status: closed`.
3. **Format** (user). Markdown with YAML frontmatter:

   ```markdown
   ---
   id: fm-zgd.3
   title: Push requests executed by the worker
   type: feature            # epic | feature | task | bug | decision | chore
   status: open             # open | in_progress | closed | deferred | on_hold
   priority: 2              # 0 (highest) .. 4
   parent: fm-zgd
   blocked_by: [fm-zgd.1]
   related: []
   supersedes: []
   discovered_from: null
   labels: []
   created: 2026-10-18
   closed: null
   close_reason: null
   ---

   ## What to build
   ...

   ## Acceptance
   - [ ] ...

   ## Notes
   - 2026-10-18 coordinator: ...
   ```

   `supersedes` is optional when reading older files (defaults to `[]`); canonical writes include it. Facts in frontmatter, prose in sections. Unknown frontmatter keys are errors. Acceptance items are Markdown checkboxes; the board shows checked/total. Notes are dated lines appended under `## Notes` (replacing `bd comments`). Other `##` sections (Design, Interfaces, Why) are free prose.
   **On hold tickets** (`fm-c2w.33`). Deliberately set-aside work uses `status: on_hold`, labelled **On hold**, distinct from a planning session's **parked** state. `foreman update <id> --status on_hold --reason "..."` requires nonblank text, stores `on_hold_reason` and an ISO date `on_hold_since`, and preserves that date while held. `new --status on_hold --reason "..."` works too. Leaving the status clears both fields. Handwritten on-hold files require the reason; the date is optional. Both fields are optional for older files, omitted when null on canonical writes. The home section includes held children without removing their epic membership; they never count as stale. `ready` still includes only open tickets. The app never writes these facts.

   Older CLIs and their `foreman check` reject the new status/keys: upgrade readers and writers before using it. Unheld canonical files retain their previous format; after resuming, the hold fields are omitted again.
4. **Ids** (user). Keep the beads scheme and every existing id: `<prefix>-<code>` for top level (short random base36, checked against existing files), `<parent>.<N>` for children (next free N). The prefix comes from the repo's `foreman.toml` entry. Ticket creation stays a main-checkout job; build sessions report fallout and the coordinator files it. A child-number collision between branches surfaces as a git add/add conflict; `foreman renumber <old> <new>` rewrites the file and every reference to it.
5. **Agent toolset** (user). The `foreman` CLI writes ticket files directly in the current checkout, with no server needed: `new`, `show`, `ls`, `ready` (open, no open blockers, not an epic), `update`, `close --reason`, `reopen`, `dep add|rm`, `note`, `tree`, `renumber`, `check`. It writes a canonical form (fixed key order, sorted lists, one trailing newline) so its edits make minimal diffs, and keeps every rule the CLI already has: never fails an agent except for invalid input, `--json` everywhere. Stage and session events still go to the server as today.
6. **Validation** (user). `foreman check` validates every file: frontmatter schema, id matches filename, parent and blockers exist, no dependency cycles, no epic as a blocker of its own child. Related, supersedes and discovered-from references must be valid ids but may name absent tickets; they do not block readiness. It runs from each repo's pre-commit hook (the hook that runs the beads export today), so a broken ticket file cannot be committed.
7. **Reading** (agent call). The board reads each configured repo's main-checkout `tickets/` folder: inotify on that one directory per repo, plus a 60-second rescan, parse into the Postgres cache, and project into the existing ticket identity (repo, id) so overlays, stages, sessions, links and requests carry over unchanged. A file that fails to parse keeps its last good version on the board and shows a per-repo error on Settings. The `bd export` reader, lock probe, process guard and export scheduler are deleted once no repo uses beads.
8. **Migration** (user). Per-repo switch in `foreman.toml` (`tickets = "files" | "beads"`) so the board reads both during the transition. Order: foreman, then skills, form-engine, dotfiles, then ui-o-matic, cooldown-o-matic, we_go_next_dev. Per repo: back up `.beads/` to a tarball outside the repo; convert every issue including closed ones (fields, dependencies of every type, comments into Notes with their dates); verify counts and a field-by-field comparison; then one commit that adds `tickets/`, removes `.beads/` and its hooks, and installs the `foreman check` pre-commit. The commit is made only in a clean checkout, after the user approves that repo.
9. **Skills and house rules** (user: switch once foreman has migrated). `to-tickets`, `dispatch` (incl. "dispatch from ready", now `foreman ready` across repos), `wayfinder` and `foreman` use the `foreman` ticket commands; the house AGENTS.md beads section becomes a short tickets section; the per-repo AGENTS beads blocks are removed during each repo's migration.

10. **Onboarding with `foreman adopt`** (user, 2026-10-18). One idempotent command onboards any repo: appends its `[[repos]]` entry to the user's config (the only config write anywhere, made by the user's own command, append-only; the web and worker never write config), migrates `.beads/` when present (backup, convert, compare, remove) or creates `tickets/`, adds a marked block to the repo's AGENTS.md pointing at the `foreman` skill (the one maintained instruction file, linked globally), installs the `foreman check` pre-commit hook, and stops before committing. Each repo cutover in Decision 8 is a run of `foreman adopt`. The CLI stays an Erlang escript on every machine. Beads `convoy` maps to `epic`, `tracks` dependencies map to `related`, and `chore` and `supersedes` retain their names. Comparison checks the mapped relations with their multiplicity; original kinds remain in the external export backup.

## Acceptance checks

1. Every repo: ticket count, statuses, parents, dependencies, labels and comment count after conversion equal the beads export taken just before (scripted comparison, output kept).
2. The board shows each migrated repo's tickets with the same stages and history as before the switch; no overlay row is orphaned by the change.
3. An edit made by hand to a ticket file in a main checkout shows on the board within 2 seconds; one made with `foreman update` likewise.
4. A malformed ticket file is refused by the pre-commit hook; if it lands anyway (hook bypassed), the board keeps the last good version and Settings names the file and error.
5. With all repos on files and nothing changing, the worker uses under 2% of a core over 10 minutes (baseline today: about 37%), and memory, task count and database size stay flat.
6. `foreman ready` across repos lists the same tickets `bd ready` did for the same state.
7. A real dispatch close-out and a `/to-tickets` run work end to end on ticket files with no `bd` on PATH.
8. No `.beads/` directory, beads hook or `bd` call remains in any repo, skill or house file; the beads reader is gone from the board.

## Verification plan

- Unit and property tests for the file format: parse/print round trip is identity on canonical files; `foreman check` rules; id generation and renumber.
- CLI tests in a temporary repo (no server): every command, canonical diffs, `--json`.
- Reader tests with a temporary directory: create, edit, rename-into-place (editor saves), delete, malformed file, rescan.
- Conversion script tests on each repo's real export (read-only), then the scripted comparison for check 1 at each cutover.
- Measurement on the installed board for check 5, same method as the 2026-10-18 baseline (systemd CPU accounting over 60 s and 10 min).

## Ask-first boundaries

- Each repo's cutover commit (one approval per repo).
- Deleting any backup tarball.
- Changing the stage machine, ticket ids, or the board's Postgres state model.
- Any write to a repo other than the one being migrated.

## Left to the builder

- Frontmatter parser and printer library choice (no new dep if an existing one fits).
- CLI flag spellings beyond the command names.
- Whether `foreman new` opens `$EDITOR`.
- Slicing into tickets.
