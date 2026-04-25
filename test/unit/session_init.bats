#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Session Init Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/session-init.sh"
  # Clean any existing markers for this PPID
  rm -f "${TMPDIR:-/tmp}"/claude-code-prompted-$$
}

teardown() {
  teardown_sandbox
}

# ── Basic Output ─────────────────────────────────────────────

@test "produces hookSpecificOutput on first run" {
  run bash -c 'echo "{\"prompt\":\"Build a login page\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "hookSpecificOutput"
}

@test "output is valid JSON" {
  local output
  output=$(echo '{"prompt":"test"}' | bash "$HOOK")
  run jq -e '.' <<< "$output"
  assert_success
}

@test "includes UserPromptSubmit event name" {
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "UserPromptSubmit"
}

# ── PPID One-Shot ────────────────────────────────────────────

@test "fires once per PPID (one-shot)" {
  # Both invocations must share the same PPID.
  # Use a wrapper script that calls the hook directly (not via $()) to preserve PPID.
  local wrapper="$TEST_SANDBOX/ppid-test.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
echo '{"prompt":"first"}' | bash "$HOOK" > "$TEST_SANDBOX/first.out"
echo '{"prompt":"second"}' | bash "$HOOK" > "$TEST_SANDBOX/second.out"
SCRIPT
  chmod +x "$wrapper"
  bash "$wrapper"

  # First should have output
  assert [ -s "$TEST_SANDBOX/first.out" ]
  # Second should be empty (marker from first run blocks it)
  refute [ -s "$TEST_SANDBOX/second.out" ]
}

# ── Autonomy-Adapted Nudge ───────────────────────────────────

@test "guided autonomy gets plain language nudge" {
  create_test_profile "vibe-coder" "guided" "simplified" "plain" "conceptual" '["core"]'
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "walk me through"
}

@test "moderate autonomy gets classify nudge" {
  create_test_profile "analyst" "moderate" "standard" "technical" "practical" '["core"]'
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "Classify this task"
}

@test "high autonomy gets tier classification nudge" {
  create_test_profile "senior-engineer" "high" "advanced"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "trivial/moderate/significant"
}

# ── Branch Reminder ──────────────────────────────────────────

@test "always includes branch reminder" {
  create_test_profile "senior-engineer" "high" "advanced"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "branch"
  assert_output --partial "main"
}

# ── Missing Profile Fallback ─────────────────────────────────

@test "falls back to high autonomy when profile missing" {
  rm -f "$CLAUDE_DIR/profile.json"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "trivial/moderate/significant"
}

# ── No persona hint (removed in v1.3.0) ─────────────────────

@test "does not include persona hint even when profile exists" {
  create_test_profile "senior-engineer" "high" "advanced" "expert" "engineering"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  refute_output --partial "Test Profile"
}

# ── Session State File ──────────────────────────────────────

@test "creates session state file with classification=unknown" {
  local wrapper="$TEST_SANDBOX/state-test.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
echo '{"prompt":"test"}' | bash "$HOOK" > /dev/null
_TMPDIR="\${TMPDIR:-/tmp}"
cat "\${_TMPDIR}/forge-session-state-\$\$" 2>/dev/null || echo "NO_STATE_FILE"
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_success
  assert_output --partial "classification=unknown"
}

@test "cleans up stale session state files" {
  local _tmpdir="${TMPDIR:-/tmp}"
  local stale="${_tmpdir}/forge-session-state-99999"
  touch "$stale"
  # Backdate by 2 days
  touch -t "$(date -v-2d +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$stale"
  echo '{"prompt":"test"}' | bash "$HOOK" > /dev/null
  [ ! -f "$stale" ]
}

# ── No document chain nudge (removed in v1.3.0) ─────────────

@test "does not include doc-chain nudge" {
  create_test_profile "senior-engineer" "high" "advanced"
  local project_dir="$TEST_SANDBOX/project"
  mkdir -p "$project_dir/.claude"
  echo '{}' > "$project_dir/package.json"

  run bash -c 'cd "$1" && echo "{\"prompt\":\"test\"}" | bash "$2"' _ "$project_dir" "$HOOK"
  assert_success
  refute_output --partial "forge init --docs"
}
