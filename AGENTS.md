# foreman

Spec: `docs/spec.md` (authoritative); design pass: `docs/design.md`; approved mockup: `docs/mockup/`.

## House rules for this app

- **On-screen text is labels and "what is this" text, status, controls, and plain instructions where the app waits on you to act** (an approval, a decision, a guided step). No taglines, slogans or values-poster lines, no subtitles or footers about how the app works, no chatty toasts; behaviour notes go in docs. Status badges ("Waiting on #5") are fine.
- **Times use the shared human format** (just now, 2 min ago, full time on hover), never raw seconds or ISO strings.
- **Stateful features sit on declared `Foreman.Fsm` machines** (workflows, sync and job lifecycles, external conversations, stateful UI); the house code-review baseline treats ad hoc status fields as Important findings.
- Tickets live in each repo's `tickets/` folder (one Markdown file per ticket), written by the `foreman` CLI or by hand and validated by `foreman check`; the app reads them and never writes them. Board state (stages, sessions, requests) is Postgres only.
- LiveView self-redirects on WSL clock rollback: see `docs/known-issues.md` for the test-only signing allowance and production reload behavior.

This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Phoenix, Elixir, Ecto, HEEx and LiveView rules: `CODING_STANDARDS.md` (read it before writing LiveView, HEEx, forms or Ecto code; reviewers check against it).

<!-- BEGIN FOREMAN -->
## Tickets

Use the globally linked `foreman` skill (`~/.agents/skills/foreman/SKILL.md`).
<!-- END FOREMAN -->
