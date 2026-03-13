#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Architect Gate Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/architect-gate.sh"
}

teardown() {
  teardown_sandbox
}

# ── Gate 1: Plan File Validation ─────────────────────────────

@test "blocks plan file without Architect Review section (Write)" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/test.md\",\"content\":\"# Plan\nJust a plan\"}}" | bash "$0"' "$HOOK"
  assert_failure 2
  assert_output --partial "BLOCKED"
  assert_output --partial "Architect Review"
}

@test "allows plan file WITH Architect Review section (Write)" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/test.md\",\"content\":\"# Plan\n## Architect Review\nApproved\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}

@test "blocks Edit to plan file without Architect Review in new_string or existing file" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/test.md\",\"new_string\":\"some changes\"}}" | bash "$0"' "$HOOK"
  assert_failure 2
}

@test "allows Edit to plan file with Architect Review in new_string" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/test.md\",\"new_string\":\"## Architect Review\nApproved\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}

@test "allows Edit to plan file when existing file already has Architect Review" {
  echo "## Architect Review" > "$CLAUDE_DIR/plans/test.md"
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'$CLAUDE_DIR'/plans/test.md\",\"new_string\":\"minor edit\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}

@test "allows plan file with no content and no new_string" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/plans/test.md\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}

# ── Gate 2: Source File Classification Nudge ─────────────────

@test "nudges on first source file edit" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/src/app.ts\"}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "classified this task"
}

@test "does not nudge on second source file edit (PPID marker)" {
  # First edit creates marker
  echo '{"tool_input":{"file_path":"/project/src/app.ts"}}' | bash "$HOOK" 2>/dev/null
  # Second edit should be silent
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/src/other.ts\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified this task"
}

# ── File Type Exclusions ─────────────────────────────────────

@test "skips .claude/ paths" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified"
}

@test "skips .md files" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/README.md\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified"
}

@test "skips .lock files" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/package-lock.json.lock\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified"
}

@test "skips node_modules paths" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/node_modules/foo/index.js\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified"
}

@test "skips non-src .json files" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"/project/tsconfig.json\"}}" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
  refute_output --partial "classified"
}
