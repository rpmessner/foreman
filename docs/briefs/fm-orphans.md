You are a build session in foreman (~/dev/utils/fm-orphans, a git worktree on branch `fm-orphans`). A coordinator session dispatched you and will read your output. Work autonomously; ask only when a decision is genuinely the user's. Three other builds run in sibling worktrees (fm-cleanenv, fm-orphans, fm-deploy, fm-age minus yours); keep shared-file edits small and additive.

## Goal
An answered request that no live wait holds is marked 'answer not picked up': it stays in Needs you under its own heading with the answer shown, and one notification tells the coordinator which session and ticket it belongs to. A later wait on that request consumes it and clears the mark. This closes the gap where fm-zgd.7's build had stopped waiting when the user answered, and nobody ever saw the answer.

## Read first
AGENTS.md, CODING_STANDARDS.md (Phoenix/LiveView rules, checked at review), docs/spec.md sections relevant to this ticket, `foreman show fm-zpn` (body and notes). lib/foreman/request.ex (the request lifecycle machine) and the wait path (`foreman wait`, how a wait is recorded and when it times out), Needs you (needs_you_live.ex, request_card), the notification path, the sessions/stage model for 'reported/exited/gone'. Prior reports: docs/sessions/bb-inbox.md and docs/sessions/fm-requests.md if present.

## Tickets
fm-zpn (ticket files; the coordinator already claimed it). The coordinator files new tickets and closes this one; report proposed new work instead of filing it.

## Skills
- `tdd` at these seams: the request machine's new guarded transitions (answered with a live wait vs. no live wait; a later wait clearing the mark), the 'live wait' predicate, Needs you rendering, the one-shot notification. Write the test against the declared signature first; add any stub body as its own edit under 10 lines (pi's write guard rejects larger placeholder diffs).
- `verify-before-claiming` before writing the report.
- `code-review` on your own diff against bb63971ecc2fc25d10c73000857c45516f3d9d86 before printing the marker: Standards (house rule: nontrivial state sits on a declared Foreman.Fsm table), Spec (fm-zpn), Risk (the request lifecycle machine, persistence of request state, notifications (once only), concurrency between an answer and a wait arriving together). Run the axes one after another in this session; spawn no subagents. Fix every Critical and Important finding, then re-run the gate.

## Decisions already made
- The rule is a guarded transition on the declared request machine, not a side check or a cron sweep alone; if detection needs a timer (wait timed out with no later wait), say how it is driven.
- 'No live wait' means: the asking session is reported, exited or gone, or its last wait on this request ended (timeout or exit) with no later wait.
- Schema change allowed only if the existing columns cannot hold the mark; if needed, ask first through the board.

## Rules
No commits, pushes, deploys or release installs. Do not touch the live foreman on 4747, its database, the `-L foreman` tmux server's existing sessions, ~/.config/foreman, ~/.config/devserve or the skills repo. Do not create or remove git worktrees of real repos except scratch repos under /tmp for tests. Use /usr/bin/rm, not rm. Never print secret values or token-file contents.

## Browser checks
For a registered app, use the `devserve` skill. In this worktree run `FOREMAN_SESSION=fm-orphans devserve up` for browser checks and use the printed URL. Confirm `devserve ls --json` shows this worktree with owner `fm-orphans`; report its unit, URL, database, and browser evidence. The preview has no API token setting yet, so authenticated JSON API calls return 401: check pages in the browser, and say in the report which API paths you could not exercise. If startup or ownership verification fails, report the blocker rather than improvising a server. Leave preview cleanup to coordinator close-out. Screenshot light and dark; be picky about the UI.

## Build loop
Use the `foreman` skill's best-effort sender for `foreman progress fm-zpn "<milestone; next step>"` at milestones; warnings never block work.
For a build-time question you cannot answer, run `foreman ask decision fm-zpn --question "<question>" --option "<A>" --option "<B>" --recommendation "<A>"` directly, then `foreman wait <returned-request-id> --timeout 7200` in your shell, not through the sender and not as a question in this pane. Follow the `foreman` skill's approval outcomes: resume only with `state: answered`, using `outcome.answer` and `note`; exit 0 alone is not an answer. Keep the ID and re-wait after a timeout. Report an unavailable inbox as a blocker rather than guessing. If a wait times out, stay in the wait loop; never write the final report while a question is open.

## Done when
- Machine tests for every new row, including the race of an answer and a wait arriving together.
- LiveView test: Needs you shows the not-picked-up section with ticket, session and the answer.
- Notification fires once per answer (test).
- End-to-end in the preview: ask, wait with a short timeout, mark the session reported, answer; the section and notification appear; a new wait consumes the answer and clears it.
- `mix precommit` green with zero warnings.
Work until every item above holds. Hand off early only near your context limit (above about 85%), at a clean, green point, with a precise list of what remains; a pure table without its executor is not a stopping point.

## Report back
Write docs/sessions/fm-orphans.md: what changed, evidence, review findings per axis with what you fixed and what you left open, proposed follow-ups, final gate output. Use the `foreman` skill's best-effort sender for `foreman report fm-zpn --path docs/sessions/fm-orphans.md`; warnings never block the marker. Then print FM-ORPHANS DONE alone on the last line.
