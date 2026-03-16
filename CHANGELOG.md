# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Tightened secret-filter patterns to reduce false positives on regex strings and bare keyword assignments
- Decomposed command-guard rm detection to support long-form GNU flags (`--recursive`, `--force`)
- Added `--recursive` detection to chmod 777 guard
- Split `cmd-install.sh` into three focused modules (orchestrator, wizard, health checks)

### Added
- ShellCheck linting job in CI
- CHANGELOG.md

## [1.2.0] - 2025-05-15

### Added
- Document chain scaffolding (`forge init --docs`, `--skip-docs`) with layered discovery
- Windows (Git Bash) support with `\r` stripping for jq output
- Parallel plugin installation for faster setup
- `--dry-run` flag for `forge install`
- Custom profile saving to user space
- Bash and zsh shell completions
- `forge status` subcommand
- `forge-update-check` hook for version advisory
- `db-guard` hook for destructive SQL prevention
- `secret-filter` hook for credential detection
- `command-guard` hook for dangerous bash commands

### Changed
- Test suites run in parallel (70s → 35s)
- Upgraded `actions/checkout` to v5 for Node.js 22+

### Fixed
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

[Unreleased]: https://github.com/nickt92/claude-code-forge/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/nickt92/claude-code-forge/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/nickt92/claude-code-forge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/nickt92/claude-code-forge/releases/tag/v1.0.0
