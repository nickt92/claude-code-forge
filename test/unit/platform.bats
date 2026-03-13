#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Platform utilities tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/platform.sh"
}

teardown() {
  teardown_sandbox
}

# ── detect_platform ──────────────────────────────────────────

@test "detect_platform returns macos or linux on supported systems" {
  run detect_platform
  assert_success
  assert_output --regexp '^(macos|linux|wsl)$'
}

@test "detect_platform output is non-empty" {
  run detect_platform
  assert_success
  refute_output ''
}

# ── get_temp_dir ─────────────────────────────────────────────

@test "get_temp_dir returns an existing directory" {
  run get_temp_dir
  assert_success
  assert [ -d "$output" ]
}

@test "get_temp_dir falls back to /tmp when TMPDIR is unset" {
  unset TMPDIR
  run get_temp_dir
  assert_success
  assert_output '/tmp'
}

@test "get_temp_dir uses TMPDIR when set" {
  export TMPDIR="$TEST_SANDBOX/custom-tmp"
  mkdir -p "$TMPDIR"
  run get_temp_dir
  assert_success
  assert_output "$TEST_SANDBOX/custom-tmp"
}

# ── resolve_path ─────────────────────────────────────────────

@test "resolve_path resolves a real file" {
  local test_file="$TEST_SANDBOX/testfile.txt"
  touch "$test_file"
  run resolve_path "$test_file"
  assert_success
  assert_output --partial "testfile.txt"
}

# ── check_platform ───────────────────────────────────────────

@test "check_platform succeeds on supported platforms" {
  # Define color vars that check_platform expects
  YELLOW='' RST='' RED=''
  run check_platform
  assert_success
}
