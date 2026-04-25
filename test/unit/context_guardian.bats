#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Context Budget Guardian Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/context-guardian.sh"
  _TMPDIR="${TMPDIR:-/tmp}"
  # Clean markers
  rm -f "$_TMPDIR"/claude-code-plan-approved-*
}

teardown() {
  rm -f "${_TMPDIR:-/tmp}"/claude-code-plan-approved-*
  teardown_sandbox
}

# ── ExitPlanMode mode ────────────────────────────────────────

@test "exitplan: produces hookSpecificOutput" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\"}" | bash "$0" exitplan' "$HOOK"
  assert_success
  assert_output --partial "hookSpecificOutput"
}

@test "exitplan: output is valid JSON" {
  local output
  output=$(echo '{"tool_name":"ExitPlanMode"}' | bash "$HOOK" exitplan)
  run jq -e '.' <<< "$output"
  assert_success
}

@test "exitplan: includes PostToolUse event name" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\"}" | bash "$0" exitplan' "$HOOK"
  assert_success
  assert_output --partial "PostToolUse"
}

@test "exitplan: suggests /clear for fresh context" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\"}" | bash "$0" exitplan' "$HOOK"
  assert_success
  assert_output --partial "/clear"
}

@test "exitplan: mentions plan file and auto-memory persistence" {
  run bash -c 'echo "{\"tool_name\":\"ExitPlanMode\"}" | bash "$0" exitplan' "$HOOK"
  assert_success
  assert_output --partial "plan file"
  assert_output --partial "auto-memory"
}

@test "exitplan: creates PPID marker" {
  # Run in a wrapper so exitplan and marker check share the same PPID
  local wrapper="$TEST_SANDBOX/exitplan-marker.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
echo '{}' | bash "$HOOK" exitplan > /dev/null
_TMPDIR="\${TMPDIR:-/tmp}"
[ -f "\${_TMPDIR}/claude-code-plan-approved-\$\$" ] && echo "MARKER_EXISTS" || echo "NO_MARKER"
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_success
  assert_output --partial "MARKER_EXISTS"
}

# ── PreCompact mode: with marker ─────────────────────────────
# Uses wrapper scripts so exitplan + precompact share the same PPID

@test "precompact: blocks when plan marker exists" {
  local wrapper="$TEST_SANDBOX/precompact-block.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
# Create marker for this shell's PID (hook will see it via PPID)
_TMPDIR="\${TMPDIR:-/tmp}"
touch "\${_TMPDIR}/claude-code-plan-approved-\$\$"
echo '{}' | bash "$HOOK" precompact
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_failure 2
}

@test "precompact: block output includes reason" {
  local wrapper="$TEST_SANDBOX/precompact-reason.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
_TMPDIR="\${TMPDIR:-/tmp}"
touch "\${_TMPDIR}/claude-code-plan-approved-\$\$"
echo '{}' | bash "$HOOK" precompact 2>/dev/null || true
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_output --partial "Plan just approved"
}

@test "precompact: block output is valid JSON" {
  local wrapper="$TEST_SANDBOX/precompact-json.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
_TMPDIR="\${TMPDIR:-/tmp}"
touch "\${_TMPDIR}/claude-code-plan-approved-\$\$"
echo '{}' | bash "$HOOK" precompact 2>/dev/null || true
SCRIPT
  chmod +x "$wrapper"
  local output
  output=$(bash "$wrapper")
  run jq -e '.' <<< "$output"
  assert_success
}

@test "precompact: block output contains decision field" {
  local wrapper="$TEST_SANDBOX/precompact-decision.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
_TMPDIR="\${TMPDIR:-/tmp}"
touch "\${_TMPDIR}/claude-code-plan-approved-\$\$"
echo '{}' | bash "$HOOK" precompact 2>/dev/null || true
SCRIPT
  chmod +x "$wrapper"
  local output
  output=$(bash "$wrapper")
  run jq -r '.decision' <<< "$output"
  assert_output "block"
}

# ── PreCompact mode: without marker ──────────────────────────

@test "precompact: allows when no marker exists" {
  run bash -c 'echo "{}" | bash "$0" precompact' "$HOOK"
  assert_success
}

@test "precompact: produces no output when allowing" {
  run bash -c 'echo "{}" | bash "$0" precompact' "$HOOK"
  assert_success
  assert_output ""
}

# ── PreCompact mode: stale marker ────────────────────────────

@test "precompact: allows when marker is older than 10 minutes and removes it" {
  local wrapper="$TEST_SANDBOX/precompact-stale.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
_TMPDIR="\${TMPDIR:-/tmp}"
marker="\${_TMPDIR}/claude-code-plan-approved-\$\$"
touch "\$marker"
# Backdate marker by 15 minutes
touch -t "\$(date -v-15M +%Y%m%d%H%M.%S 2>/dev/null || date -d '15 minutes ago' +%Y%m%d%H%M.%S 2>/dev/null)" "\$marker"
echo '{}' | bash "$HOOK" precompact
# Stale marker should have been cleaned up
[ ! -f "\$marker" ] && echo "MARKER_REMOVED" || echo "MARKER_STILL_EXISTS"
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_success
  assert_output --partial "MARKER_REMOVED"
}

# ── Default mode ─────────────────────────────────────────────

@test "defaults to precompact mode when no argument given" {
  run bash -c 'echo "{}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ""
}

# ── End-to-end: exitplan then precompact ─────────────────────

@test "exitplan followed by precompact blocks compaction" {
  local wrapper="$TEST_SANDBOX/e2e-block.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
echo '{}' | bash "$HOOK" exitplan > /dev/null
echo '{}' | bash "$HOOK" precompact
SCRIPT
  chmod +x "$wrapper"
  run bash "$wrapper"
  assert_failure 2
  assert_output --partial "Plan just approved"
}
