# Contributing

Thanks for your interest in Claude Code Forge! This guide covers the basics for getting started.

## Development Setup

```bash
git clone --recursive https://github.com/nickt92/claude-code-forge.git
cd claude-code-forge
```

The `--recursive` flag pulls bats-core test submodules. If you already cloned without it:

```bash
git submodule update --init --recursive
```

### Prerequisites

- **bash** 4.0+ (macOS ships 3.2 — `brew install bash` for 5.x)
- **jq** — `brew install jq` (macOS) or `apt install jq` (Linux)
- **bats-core** — included as a git submodule, no separate install needed

## Running Tests

```bash
./test/run_tests.sh              # all tests (parallel suites)
./test/run_tests.sh unit         # unit tests only
./test/run_tests.sh integration  # integration tests only
./test/run_tests.sh validation   # validation tests only
./test/run_tests.sh test/unit/status.bats  # specific file
```

All tests run in a sandbox (`$HOME` redirected to a temp directory) — your real `~/.claude/` is never touched.

## Project Structure

| Directory | Purpose |
|:----------|:--------|
| `lib/cmd-*.sh` | Subcommands — auto-discovered by the `forge` dispatcher |
| `lib/*.sh` | Shared libraries (ui, assembly, manifest, plugins, etc.) |
| `hooks/*.sh` | Claude Code hook scripts |
| `templates/` | Profiles, sections, rules, settings template |
| `completions/` | Bash and zsh tab completion scripts |
| `test/` | bats-core test suites (unit, integration, validation) |

## Adding a Subcommand

1. Create `lib/cmd-<name>.sh` with a `cmd_<name>()` function
2. The `forge` dispatcher auto-discovers it — no registration needed
3. Add `--help` support following the existing pattern
4. Add tests in `test/unit/<name>.bats` or `test/integration/<name>.bats`
5. Update `completions/forge.bash` and `completions/forge.zsh`

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): add new feature
fix(scope): fix a bug
chore(scope): maintenance task
docs: documentation only
test: test only changes
refactor: code change that neither fixes nor adds
perf: performance improvement
```

The `commit-validator` hook enforces this format.

**Do not include AI attribution** (`Co-Authored-By: Claude`, `Generated with Claude Code`, etc.) — the `commit-validator` hook blocks it.

## Pull Requests

- Branch from `develop`, PR back to `develop`
- Keep PRs focused — one logical change per PR
- Ensure all tests pass (`./test/run_tests.sh`)
- Include tests for new functionality
- Cross-platform: changes should work on macOS, Linux, and Windows (Git Bash)

## Hook Development

Hooks are standalone bash scripts that receive JSON on stdin and communicate via exit codes and stdout JSON:

- **Exit 0** — allow (with optional `hookSpecificOutput` JSON)
- **Exit 2** — block (with error message on stderr)
- **PreToolUse** hooks can block; **PostToolUse** and **UserPromptSubmit** hooks are advisory only

See [SECURITY.md](SECURITY.md) for the full hook model and known limitations.

## Code Style

- Follow existing patterns — read the file before modifying it
- Use `ui.sh` functions (`ok`, `warn`, `fail`, `info`, `step`, `banner`, `kv`) for output
- Use `source "$FORGE_SOURCE_DIR/lib/<file>.sh"` for dependencies
- Tests use bats-assert (`assert_success`, `assert_output --partial`, `refute_output`)
- All jq calls on Windows need the `\r` wrapper (see `lib/platform.sh`)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
