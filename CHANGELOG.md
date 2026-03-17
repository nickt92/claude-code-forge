# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-03-17

### Added
- `forge-override` bypass mechanism for command-guard and db-guard hooks
- Audit logging for overrides in `~/.claude/security.log`
- `security-overrides.md` rules template for Claude behavioural constraints

### Security
- Override requires non-empty reason — bare token and whitespace-only are rejected
- Full-bypass behaviour explicitly documented in SECURITY.md
- Override mechanism, security model, and audit trail format documented

## [1.2.0] - 2025-05-15

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

## [1.1.0] - 2025-04-28

### Added
- `forge` CLI with 7 subcommands (`install`, `switch`, `doctor`, `diff`, `init`, `build`, `update`)
- 3 plugin groups (full/standard/minimal) with persona-aware defaults
- Manifest-based backup and uninstall with rollback support
- Brew-style terminal UI with progress indicators

### Fixed
- Resolved unbound variable crash in CLI
- Corrected test assertions and manifest reading order

## [1.0.0] - 2025-04-20

### Added
- Initial release with 12 persona profiles across 4 behavioral axes
- CLAUDE.md assembly engine with section composition
- Profile-driven installation to `~/.claude/`
- Settings merge with hook deduplication
- 7 rules files for engineering standards
- Onboarding wizard with role selection

[Unreleased]: https://github.com/nickt92/claude-code-forge/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/nickt92/claude-code-forge/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/nickt92/claude-code-forge/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/nickt92/claude-code-forge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nickt92/claude-code-forge/releases/tag/v1.0.0
