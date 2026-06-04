#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Plugin Groups — unit tests for lib/plugins.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/plugins.sh"
}

teardown() {
  teardown_sandbox
}

# ── Group resolution ─────────────────────────────────────────

@test "resolve_plugin_list returns plugins for 'full' group" {
  run resolve_plugin_list "full"
  assert_success
  assert_output --partial "backend-development"
  assert_output --partial "context7"
  assert_output --partial "frontend-design"
}

@test "resolve_plugin_list returns plugins for 'standard' group" {
  run resolve_plugin_list "standard"
  assert_success
  assert_output --partial "backend-development"
  # standard should NOT include hr-legal-compliance
  refute_output --partial "hr-legal-compliance"
  refute_output --partial "startup-business-analyst"
}

@test "resolve_plugin_list returns plugins for 'minimal' group" {
  run resolve_plugin_list "minimal"
  assert_success
  assert_output --partial "debugging-toolkit"
  assert_output --partial "comprehensive-review"
  assert_output --partial "context7"
  # minimal should NOT include backend-development
  refute_output --partial "backend-development"
}

@test "resolve_plugin_list falls back to full for unknown group" {
  run resolve_plugin_list "nonexistent"
  assert_success
  assert_output --partial "backend-development"
  assert_output --partial "Unknown plugin group"
}

@test "full group has 18 plugins" {
  local count
  count=$(resolve_plugin_list "full" | grep -c .)
  assert [ "$count" -eq 18 ]
}

@test "standard group has 16 plugins" {
  local count
  count=$(resolve_plugin_list "standard" | grep -c .)
  assert [ "$count" -eq 16 ]
}

@test "minimal group has 6 plugins" {
  local count
  count=$(resolve_plugin_list "minimal" | grep -c .)
  assert [ "$count" -eq 6 ]
}

# ── Group names ──────────────────────────────────────────────

@test "get_plugin_group_names returns all groups" {
  run get_plugin_group_names
  assert_success
  assert_output --partial "full"
  assert_output --partial "standard"
  assert_output --partial "minimal"
}

# ── Default plugin group from profile ────────────────────────

@test "get_default_plugin_group returns full for senior-engineer" {
  run get_default_plugin_group "$PROFILES_DIR/senior-engineer.json"
  assert_output "full"
}

@test "get_default_plugin_group returns minimal for vibe-coder" {
  run get_default_plugin_group "$PROFILES_DIR/vibe-coder.json"
  assert_output "minimal"
}

@test "get_default_plugin_group returns standard for designer" {
  run get_default_plugin_group "$PROFILES_DIR/designer.json"
  assert_output "standard"
}

@test "get_default_plugin_group falls back to full when field missing" {
  local temp_profile="$TEST_SANDBOX/no-group-profile.json"
  echo '{"schema_version": 1, "persona": "test"}' > "$temp_profile"
  run get_default_plugin_group "$temp_profile"
  assert_output "full"
}

# ── Parallel install config ──────────────────────────────────

@test "MAX_PARALLEL defaults to 4" {
  assert [ "$MAX_PARALLEL" -eq 4 ]
}

@test "MAX_PARALLEL is configurable" {
  MAX_PARALLEL=2
  assert [ "$MAX_PARALLEL" -eq 2 ]
  MAX_PARALLEL=4  # reset
}

@test "install_plugins handles empty list gracefully" {
  # Mock claude command to avoid needing real CLI
  claude() { return 0; }
  export -f claude

  run install_plugins ""
  # Should not crash
  assert_success
}

# ── Install invocation contract (regression guard) ───────────
# Locks the exact CLI flow against the current Claude Code: marketplaces are
# registered first via `plugin marketplace add <source>`, then plugins are
# installed via `plugin install <name>@<marketplace> --scope user`. The dead
# `claude plugins add` verb must never reappear.

# Stateful `claude` mock for install_plugins tests:
#   - records argv to $CLAUDE_CALLS
#   - `marketplace add <source>` makes the mapped marketplace NAME appear in
#     subsequent `marketplace list` output (mirrors real source->name
#     resolution) — unless $MOCK_ADD_NO_REGISTER is set (simulates a source
#     that resolves to an unexpected name)
#   - `plugin install <plugin>` fails with multiline stderr when $* matches
#     the substring in $MOCK_INSTALL_FAIL
# Also stubs progress_*/warn so output is deterministic.
mock_claude() {
  CLAUDE_CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CLAUDE_CALLS"
  MKT_STATE="$BATS_TEST_TMPDIR/marketplaces"; : > "$MKT_STATE"
  progress_start() { :; }
  progress_tick() { :; }
  progress_done() { echo "DONE: $*"; }
  warn() { echo "WARN: $*"; }
  claude() {
    printf '%s\n' "$*" >> "$CLAUDE_CALLS"
    case "$*" in
      *"marketplace list"*)
        cat "$MKT_STATE" ;;
      *"marketplace add "*)
        [ -n "${MOCK_ADD_NO_REGISTER:-}" ] && return 0
        case "$*" in
          *"wshobson/agents"*) echo "  ❯ claude-code-workflows" >> "$MKT_STATE" ;;
          *"anthropics/claude-plugins-official"*) echo "  ❯ claude-plugins-official" >> "$MKT_STATE" ;;
        esac ;;
      *"plugin install "*)
        if [ -n "${MOCK_INSTALL_FAIL:-}" ]; then
          case "$*" in
            *"$MOCK_INSTALL_FAIL"*) printf 'network unreachable\n  at fetch (node:internal)\n' >&2; return 1 ;;
          esac
        fi ;;
    esac
    return 0
  }
}

@test "install_plugins registers marketplaces then installs with --scope user" {
  mock_claude

  install_plugins "backend-development@claude-code-workflows
context7@claude-plugins-official"

  # Marketplace sources came from templates/marketplaces.json, not repo paths.
  grep -qF "plugin marketplace add wshobson/agents" "$CLAUDE_CALLS"
  grep -qF "plugin marketplace add anthropics/claude-plugins-official" "$CLAUDE_CALLS"

  # Installs use name@marketplace and explicit user scope.
  grep -qF "plugin install backend-development@claude-code-workflows --scope user" "$CLAUDE_CALLS"
  grep -qF "plugin install context7@claude-plugins-official --scope user" "$CLAUDE_CALLS"

  # The removed verb must never be used again.
  refute grep -qE "plugins add|plugin add " "$CLAUDE_CALLS"

  # Every marketplace add precedes every install (no fan-out race).
  local last_add first_install
  last_add=$(grep -n "marketplace add" "$CLAUDE_CALLS" | tail -1 | cut -d: -f1)
  first_install=$(grep -n "plugin install" "$CLAUDE_CALLS" | head -1 | cut -d: -f1)
  assert [ "$last_add" -lt "$first_install" ]
}

@test "install_plugins skips adding an already-registered marketplace" {
  mock_claude
  # Pre-register the workflows marketplace.
  echo "  ❯ claude-code-workflows" > "$MKT_STATE"

  install_plugins "backend-development@claude-code-workflows"

  refute grep -qF "marketplace add" "$CLAUDE_CALLS"
  grep -qF "plugin install backend-development@claude-code-workflows --scope user" "$CLAUDE_CALLS"
}

@test "install_plugins surfaces real failure reason instead of silent skip" {
  # Multiline stderr (as a Node CLI emits) must be flattened so the failed
  # plugin id and reason stay on a single, readable line.
  mock_claude
  MOCK_INSTALL_FAIL="install backend-development"

  run install_plugins "backend-development@claude-code-workflows
context7@claude-plugins-official"

  assert_success
  assert_output --partial "DONE: 1 plugins installed (1 failed)"
  # Plugin id and reason on ONE line — would split across lines without flattening.
  assert_line --partial "✗ backend-development@claude-code-workflows: network unreachable"
}

@test "install_plugins fails plugins when their marketplace resolves to an unexpected name" {
  # `marketplace add` succeeds but the expected name never appears in `list`
  # (source resolved to a different marketplace name). Plugins must fail fast
  # with one clear reason — and no install should be attempted.
  mock_claude
  MOCK_ADD_NO_REGISTER=1

  run install_plugins "backend-development@claude-code-workflows
context7@claude-plugins-official"

  assert_success
  assert_output --partial "DONE: 0 plugins installed (2 failed)"
  assert_line --partial "✗ backend-development@claude-code-workflows: added but not listed under expected name"
  # The marketplace add was attempted, but no plugin install followed.
  grep -qF "marketplace add wshobson/agents" "$CLAUDE_CALLS"
  refute grep -qF "plugin install" "$CLAUDE_CALLS"
}

@test "install_plugins does not crash under set -u when every plugin fails" {
  # `forge` runs with `set -euo pipefail`. When all plugins fail in Phase 1
  # no install is spawned, so the "wait for remaining" loop expands an empty
  # pids array — which aborts under set -u (bash 3.2) without the guard.
  # bats bodies don't enable set -u by default, so assert it explicitly here.
  mock_claude
  MOCK_ADD_NO_REGISTER=1

  set -u
  install_plugins "backend-development@claude-code-workflows"
  set +u

  assert_equal "$PLUGINS_INSTALLED" 0
  assert_equal "$PLUGINS_FAILED" 1
}
