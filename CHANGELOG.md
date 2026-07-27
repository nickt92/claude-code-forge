# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.1] - 2026-07-27

### Fixed
- `forge stats` reported an install from today as "1 day ago". The manifest
  timestamp is UTC but was being read in local time, and on macOS the baseline
  drifted through the day rather than sitting at midnight
- **The `if:` hook filter never worked.** It was written onto the hook *group*,
  but Claude Code only accepts it on individual hook entries, so it was silently
  discarded — `commit-validator` and `db-guard` ran on every single Bash call
  instead of only on git commits and database commands. The v1.3.0 notes claimed
  a 95-99% reduction in process spawns from this; that reduction never happened.
  It does now
- **forge could not update its own hooks on an existing install.** Hook groups
  were deduplicated by command string, a key that cannot express "same hook, new
  definition" — so once installed, a hook's timeout, matcher and `if` filter were
  frozen forever and the installed entry always won. This is why fixing the `if:`
  placement alone would have reached only fresh installs
- **Hooks forge stopped shipping were never removed.** A `plan-checkpoint` entry
  dropped in 1.3.0 is still registered on installed machines; the only cleanup
  was a hardcoded special case for a different hook. Removal is now driven by the
  install manifest, so it covers every hook forge has ever installed — and never
  touches a script you placed in `~/.claude/hooks/` yourself
- `secret-filter` ran its 13 credential patterns over the output of *every* tool.
  It is now scoped to the tools whose output can actually carry secrets
- **Switching or removing a permission preset could delete rules you already
  had.** forge recorded the entire resolved preset as "what forge added", so if
  you already had `Read` or `Bash(git status:*)` in your settings, forge claimed
  them — and removed them on the next preset change or uninstall. It now
  distinguishes rules it actually added from rules it merely found already
  present, and only ever removes the former

### Changed
- Manifest schema v3. The flat `permissions_preset` / `permissions_added` fields
  become a single `permissions` record carrying the preset, what forge owns,
  what it adopted, and where that record came from. Existing installs migrate
  automatically on the next `forge install`
- Migration from v2 is deliberately conservative: a v2 manifest cannot tell
  owned from adopted after the fact, so it claims only entries still present in
  your settings and marks the record `migrated` rather than implying precision
  it does not have

## [1.5.0] - 2026-07-26

Protects the config file forge shares with you, and gives you a way back.

### Added
- `forge restore` — roll `settings.json` back to an earlier snapshot.
  `--list` shows what is available with readable timestamps and marks the one
  matching your current settings; restore by name, by bare timestamp,
  `--latest`, or `--pre-install` for your settings from before forge existed
- Every operation that rewrites `settings.json` now snapshots it first, labelled
  and UTC-stamped (install, permissions, uninstall). The 20 most recent are kept.
  Previously there was exactly one restore point ever — the backup taken at
  first install — so a user installed for a year had a single snapshot from a
  year ago and no way to undo one bad operation
- `analyze`, `permissions`, `restore` and `statusline` in shell completions.
  The first three were missing entirely

### Fixed
- **Uninstall could delete hooks and plugins you added yourself.** Ownership of
  settings entries was inferred as "anything not in the backup", but the backup
  is frozen at first install — so anything you added afterwards looked like a
  forge addition, and uninstall removed it. `forge update` re-triggered this on
  every run. Ownership is now derived from what forge actually ships, so entries
  you added are neither claimed nor removed
- An entry forge shipped in an older version but no longer ships is now left in
  place rather than deleted. `forge doctor` can report it; deleting something
  forge is no longer sure it owns is the more dangerous mistake
- `forge restore` and the snapshot history are reachable from the CLI, not just
  when a library happens to be pre-loaded — the command resolved its history
  directory from an unset variable and silently found nothing

## [1.4.0] - 2026-07-26

Major UI/UX overhaul of Forge Desktop (macOS app) plus new in-app capabilities,
and a round of correctness work on the test suite and the permissions record.

### Added
- Design system v2 for Forge Desktop: spacing and typography scales, elevation
  with dark-mode-aware shadows, semantic colors, WCAG AA text-grade brand
  orange, motion tokens that honor Reduce Motion, and a component library
  (cards, four button styles with hover states, unified sheet chrome, skeleton
  loading, branded empty states, status badges)
- Brand accent color: stock buttons, selections, and toggles now render in
  forge ember instead of system blue
- Instant launch: the dashboard renders from the last successful scan
  immediately and refreshes in the background; a failed refresh keeps the
  usable data on screen with a non-destructive warning
- Data-driven permission preset picker in Settings and the setup wizard, fed
  by `forge permissions --list --json` (labels, tiers, rule counts, and the
  inheritance chain come from the CLI)
- Status card in Settings: installed vs source CLI version, persona, plugin
  and hook counts, install date — with a one-click, confirmed in-app
  `forge update` flow and update log
- "Update ready to install" indicators in the dashboard health card and menu
  bar, replacing the terminal nag loop
- Native persona builder: three-step wizard creating custom personas through
  the new non-interactive `forge build` flags (`--name`, axis flags,
  `--quality`, `--plugins`, `--switch/--no-switch`, `--force`)
- Menu bar deep links: repos needing attention open the dashboard with that
  repository selected
- Version-sync test guard: CLI, app, and README versions can no longer drift
- CI now runs on release and hotfix branches, and runs the Swift suite. Release
  branches previously ran nothing, and the desktop tests had never run in CI
- `test/validation/bats_namespace.bats` — fails the build if shipped code
  defines a function name owned by the bats test helpers

### Changed
- Every screen overhauled on the design system: dashboard sidebar with
  skeleton loading and animated health card, repo detail with hero header and
  adaptive layout, findings with severity edge bars and hover states, unified
  Doctor/Telemetry/Persona/Setup sheet chrome, restyled menu bar
- VoiceOver labels on all icon-only controls; decorative elements hidden from
  assistive tech; all animations respect Reduce Motion

### Fixed
- Desktop app version drift (the app claimed 1.3.0 while the CLI was 1.3.1)
- CLI failures from `forge update` and `forge build` now reach the app with
  their real error message instead of an empty string
- `forge build` with a value flag missing its value fails with a clear message
  instead of aborting silently
- Doctor sheet could be presented twice from different windows
- Test assertions were silently disabled. `lib/ui.sh` defined `fail()`, which is
  also the function bats-support uses to fail a test, so in the 24 of 44 test
  files that source it every assertion reported success regardless of outcome.
  The suite claimed 722 passing while 13 were broken. Renamed to `forge_fail()`
  and added a guard that compares every bats helper name against every shipped
  function name, so the whole class of collision now fails the build
- Switching permission presets could stop working. `forge update` reinstalls
  without `--permissions`, and the manifest rewrite dropped the record of what
  forge had added — after which the removal step no-ops and merging can only
  add. Presets became one-way and rules forge had added could not be withdrawn.
  The record now survives reinstall
- `forge stats --session` exited 1 on success whenever a session had no
  overrides, which is the normal case
- `forge stats --hooks` and `--session` crashed with "integer expression
  expected". `grep -c` prints `0` *and* exits non-zero when nothing matches, so
  the fallback appended a second `0`
- Intermittent test failures from three suites sharing one temp directory: one
  suite's teardown could delete a marker file belonging to a test still running
  in another

## [1.3.1] - 2026-06-04

### Fixed
- Plugin installation now works with current Claude Code. `forge install` relied on a plugin command that newer Claude Code removed, so it silently installed no plugins and reported nothing wrong. Installation now registers each plugin's marketplace and installs through the current command, and surfaces the real reason when a plugin can't be installed instead of skipping it silently.

### Changed
- Plugin installation confirms each marketplace registered under its expected name before installing. If a marketplace source resolves to an unexpected name, you get one clear error up front instead of a string of confusing per-plugin failures.

## [1.3.0] - 2026-04-25

### Added
- Context Budget Guardian hook — blocks compaction after plan approval, suggests `/clear` instead
- `if` fields on commit-validator and db-guard hooks to reduce process spawns (~95-99% fewer)
- Effort level indicator in status line (shows reasoning depth next to model badge)
- `workspace.git_worktree` detection in status line (eliminates subprocess spawns)

### Changed
- Replaced `plan-checkpoint` PostToolUse hook with `context-guardian` PreCompact hook (blocking capability)
- Session-init hook streamlined — removed persona hint and document chain nudge (reduces token injection)
- Backup-transcript hook no longer prunes old backups (delegated to Claude Code's `cleanupPeriodDays`)

### Fixed
- Status line context percentage now trusts Claude Code's `used_percentage` directly instead of recomputing against effective capacity
- Status line token speed discards stale samples (>30s gap) to prevent incorrect readings after terminal backgrounding
- Status line cache ratio denominator now includes all token types (input + cache creation + cache read)

### Removed
- `plan-checkpoint.sh` hook (superseded by `context-guardian.sh`)
- Persona hint output from session-init hook (CLAUDE.md already provides persona context)
- Document chain nudge from session-init hook (`forge init --docs` remains as explicit command)

## [1.2.1] - 2026-03-17

### Added
- `forge-override` bypass mechanism for command-guard and db-guard hooks
- Audit logging for overrides in `~/.claude/security.log`
- `security-overrides.md` rules template for Claude behavioural constraints

### Security
- Override requires non-empty reason — bare token and whitespace-only are rejected
- Full-bypass behaviour explicitly documented in SECURITY.md
- Override mechanism, security model, and audit trail format documented

## [1.2.0] - 2026-03-17

### Added
- `forge stats` subcommand — installation overview, security event distribution, session backup metrics
- `forge export` subcommand — package forge installation into portable tar.gz archive
- `bar()` UI primitive for proportional distribution charts
- `format_bytes()` shared utility in platform module
- Document chain scaffolding (`forge init --docs`, `--skip-docs`) with layered discovery
- Windows (Git Bash) support with `\r` stripping for jq output
- Parallel plugin installation for faster setup
- `--dry-run` flag for `forge install`
- Custom profile saving to user space
- Bash and zsh shell completions (including `stats` and `export`)
- `forge status` subcommand
- `forge-update-check` hook for version advisory
- `db-guard` hook for destructive SQL prevention
- `secret-filter` hook for credential detection
- `command-guard` hook for dangerous bash commands
- ShellCheck linting job in CI
- CHANGELOG.md

### Changed
- Tightened secret-filter patterns to reduce false positives on regex strings and bare keyword assignments
- Decomposed command-guard rm detection to support long-form GNU flags (`--recursive`, `--force`)
- Added `--recursive` detection to chmod 777 guard
- Split `cmd-install.sh` into three focused modules (orchestrator, wizard, health checks)
- Test suites run in parallel (70s → 35s)
- Upgraded `actions/checkout` to v5 for Node.js 22+

### Fixed
- Statusline: use absolute git-dir for reliable rebase/merge/cherry-pick state detection
- Statusline: strip `\r` from jq and git output for Windows/Git Bash compatibility
- Closed separated-flags and `.env` variant bypasses in command-guard
- Hardened tests for cross-platform CI

### Security
- Added SECURITY.md documenting hook limitations and threat model

## [1.1.0] - 2026-03-16

### Added
- `forge` CLI with 7 subcommands (`install`, `switch`, `doctor`, `diff`, `init`, `build`, `update`)
- 3 plugin groups (full/standard/minimal) with persona-aware defaults
- Manifest-based backup and uninstall with rollback support
- Brew-style terminal UI with progress indicators

### Fixed
- Resolved unbound variable crash in CLI
- Corrected test assertions and manifest reading order

## [1.0.0] - 2026-03-14

### Added
- Initial release with 12 persona profiles across 4 behavioral axes
- CLAUDE.md assembly engine with section composition
- Profile-driven installation to `~/.claude/`
- Settings merge with hook deduplication
- 7 rules files for engineering standards
- Onboarding wizard with role selection

[Unreleased]: https://github.com/nickt92/claude-code-forge/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/nickt92/claude-code-forge/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/nickt92/claude-code-forge/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/nickt92/claude-code-forge/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/nickt92/claude-code-forge/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/nickt92/claude-code-forge/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/nickt92/claude-code-forge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nickt92/claude-code-forge/releases/tag/v1.0.0
