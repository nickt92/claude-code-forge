#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Plan Checkpoint Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/plan-checkpoint.sh"
}

teardown() {
  teardown_sandbox
}

# ── Basic Output ─────────────────────────────────────────────

@test "produces hookSpecificOutput for ExitPlanMode" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "hookSpecificOutput"
}

@test "output is valid JSON" {
  local output
  output=$(echo '{"tool_name":"ExitPlanMode","tool_input":{},"tool_response":{}}' | bash "$HOOK")
  run jq -e '.' <<< "$output"
  assert_success
}

@test "includes PostToolUse event name" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "PostToolUse"
}

@test "suggests /clear for fresh context" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "/clear"
}

@test "mentions plan file persistence" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "plan file"
  assert_output --partial "auto-memory"
}

# ── Guard: non-ExitPlanMode tools ────────────────────────────

@test "produces no output for other tools" {
  run bash -c 'echo "{\"tool_name\":\"Write\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ""
}

@test "produces no output for EnterPlanMode" {
  run bash -c 'echo "{\"tool_name\":\"EnterPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ""
}

@test "produces no output when tool_name is missing" {
  run bash -c 'echo "{\"tool_input\":{}}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ""
}

# ── Always exits 0 (advisory, never blocks) ─────────────────

@test "exits 0 for ExitPlanMode" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
}

@test "exits 0 for non-matching tools" {
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{},\"tool_response\":{}}" | bash "$0"' "$HOOK"
  assert_success
}
