#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Forge Update Check Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/forge-update-check.sh"
  export CLAUDE_DIR="$TEST_SANDBOX/.claude"

  # Clean any existing markers for this PPID
  rm -f "${TMPDIR:-/tmp}"/claude-forge-update-$$

  # Create a forge source sandbox with a known version
  FORGE_SOURCE="$TEST_SANDBOX/forge-source"
  mkdir -p "$FORGE_SOURCE/lib"
  echo 'FORGE_VERSION="${FORGE_VERSION:-1.2.0}"' > "$FORGE_SOURCE/lib/manifest.sh"
}

teardown() {
  rm -f "${TMPDIR:-/tmp}"/claude-forge-update-*
  teardown_sandbox
}

# Helper: create manifest with given installed version and source dir
create_manifest() {
  local version="${1:-1.1.0}"
  local source_dir="${2:-$FORGE_SOURCE}"
  mkdir -p "$CLAUDE_DIR/forge-backup"
  cat > "$CLAUDE_DIR/forge-backup/manifest.json" <<EOF
{
  "manifest_version": 2,
  "forge_version": "${version}",
  "source_dir": "${source_dir}",
  "install_timestamp": "2026-01-01T00:00:00Z"
}
EOF
}

# ── Version Mismatch ──────────────────────────────────────────

@test "advises update when versions differ" {
  create_manifest "1.1.0"
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "Forge update available"
  assert_output --partial "1.1.0"
  assert_output --partial "1.2.0"
}

@test "output is valid JSON on version mismatch" {
  create_manifest "1.0.0"
  local output
  output=$(echo '{"prompt":"test"}' | bash "$HOOK")
  run jq -e '.' <<< "$output"
  assert_success
}

@test "includes UserPromptSubmit event name" {
  create_manifest "1.0.0"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "UserPromptSubmit"
}

@test "suggests forge install command" {
  create_manifest "1.0.0"
  run bash -c 'echo "{\"prompt\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output --partial "forge install"
}

# ── Same Version ──────────────────────────────────────────────

@test "silent when versions match" {
  create_manifest "1.2.0"
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

# ── Marker File (Once Per Session) ─────────────────────────────

@test "fires once per session (PPID marker)" {
  create_manifest "1.1.0"
  local wrapper="$TEST_SANDBOX/ppid-test.sh"
  cat > "$wrapper" <<SCRIPT
#!/bin/bash
export CLAUDE_DIR="$CLAUDE_DIR"
echo '{"prompt":"first"}' | bash "$HOOK" > "$TEST_SANDBOX/first.out"
echo '{"prompt":"second"}' | bash "$HOOK" > "$TEST_SANDBOX/second.out"
SCRIPT
  chmod +x "$wrapper"
  bash "$wrapper"

  # First should have output
  assert [ -s "$TEST_SANDBOX/first.out" ]
  # Second should be empty (marker blocks it)
  refute [ -s "$TEST_SANDBOX/second.out" ]
}

# ── Missing Manifest ─────────────────────────────────────────

@test "silent when manifest is missing" {
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

# ── Missing Source Dir ────────────────────────────────────────

@test "silent when source_dir is missing from manifest" {
  mkdir -p "$CLAUDE_DIR/forge-backup"
  cat > "$CLAUDE_DIR/forge-backup/manifest.json" <<EOF
{
  "manifest_version": 2,
  "forge_version": "1.1.0",
  "install_timestamp": "2026-01-01T00:00:00Z"
}
EOF
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

@test "silent when source directory does not exist" {
  create_manifest "1.1.0" "/nonexistent/path"
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

@test "silent when source manifest.sh does not exist" {
  create_manifest "1.1.0" "$TEST_SANDBOX/empty-source"
  mkdir -p "$TEST_SANDBOX/empty-source/lib"
  run bash -c 'echo "{\"prompt\":\"hello\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}
