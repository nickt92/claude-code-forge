# Commit Standards & Delivery

## Commit Rules

- **NEVER** add AI attribution — no `Co-Authored-By: Claude`, no "Generated with Claude Code"
- **Conventional + scoped** — `feat(auth):`, `fix(payments):`, `chore(deps):`, `docs:`, `test:`, `refactor:`
- **Atomic** — one logical change per commit. NEVER bundle unrelated changes.
- **Meaningful messages** — subject line focused on the "why". Body with bullet points for multi-part changes.
- **Breaking changes** — use `BREAKING CHANGE:` footer or `!` suffix: `feat(api)!: remove v1 endpoints`
- **Issue references** — link to issues/tickets when applicable: `Fixes #123`, `Closes #456`
- **NEVER commit** — secrets, .env files, debug/console statements, commented-out code, large binaries

## Dependency Policy

- Use the project's existing package manager. NEVER switch without discussion.
- Keep dependencies minimal. Audit before adding — justify every addition.
- Prefer well-maintained, widely-adopted libraries over niche alternatives.
- Pin major versions. Review changelogs before upgrading.

## Incremental Delivery

- Break large tasks into smaller, testable, deliverable increments.
- Each increment MUST leave the codebase in a working, deployable state.
- Prefer multiple small PRs over one massive PR.