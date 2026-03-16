#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stats — unit tests for forge stats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-stats.sh"
}

teardown() {
  teardown_sandbox
}

# ── Help & Error Handling ────────────────────────────────────

@test "stats --help shows usage" {
  run cmd_stats --help
  assert_success
  assert_output --partial "forge stats"
  assert_output --partial "security"
  assert_output --partial "sessions"
}

@test "stats fails when not installed" {
  run cmd_stats
  assert_failure
  assert_output --partial "not installed"
}

# ── Installation Section ─────────────────────────────────────

@test "stats shows installation section with persona and version" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {"a": true, "b": true}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats
  assert_success
  assert_output --partial "Installation"
  assert_output --partial "senior-engineer"
  assert_output --partial "1.1.0"
}

@test "stats shows plugin group and count" {
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {"a": true, "b": true, "c": true}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats
  assert_success
  assert_output --partial "full"
  assert_output --partial "3 enabled"
}

@test "stats shows install date with age" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats
  assert_success
  assert_output --partial "2026-01-01"
  assert_output --partial "days ago"
}

@test "stats shows file counts from manifest" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"
  # Add some files to the manifest installed section
  local tmp
  tmp=$(jq '.installed.directories.rules = ["a.md", "b.md"] | .installed.directories.hooks = ["x.sh"]' \
    "$CLAUDE_DIR/forge-backup/manifest.json")
  echo "$tmp" > "$CLAUDE_DIR/forge-backup/manifest.json"

  run cmd_stats
  assert_success
  assert_output --partial "2 rules"
  assert_output --partial "1 hooks"
}

# ── Security Section ─────────────────────────────────────────

@test "stats shows no-events message when security.log missing" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats
  assert_success
  assert_output --partial "No security events recorded."
}

@test "stats shows security event counts and bar chart" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  # Create security log with events
  cat > "$CLAUDE_DIR/security.log" <<'LOG'
2026-03-15T14:00:00Z SECRET_DETECTED tool=Edit types="aws_key"
2026-03-15T14:10:00Z SECRET_DETECTED tool=Edit types="aws_key"
2026-03-15T14:20:00Z SECRET_DETECTED tool=Write types="github_token"
LOG

  run cmd_stats
  assert_success
  assert_output --partial "3 detections"
  assert_output --partial "aws_key"
  assert_output --partial "github_token"
}

@test "stats --security shows only security section" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --security
  assert_success
  assert_output --partial "Security Events"
  refute_output --partial "Installation"
  refute_output --partial "Sessions"
}

@test "stats shows most recent event timestamp" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  cat > "$CLAUDE_DIR/security.log" <<'LOG'
2026-03-14T10:00:00Z SECRET_DETECTED tool=Edit types="aws_key"
2026-03-15T14:22:00Z SECRET_DETECTED tool=Edit types="github_token"
LOG

  run cmd_stats --security
  assert_success
  assert_output --partial "2026-03-15T14:22:00Z"
}

@test "stats handles malformed security.log lines gracefully" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  cat > "$CLAUDE_DIR/security.log" <<'LOG'
this is not a valid line
2026-03-15T14:00:00Z SECRET_DETECTED tool=Edit types="aws_key"
another bad line
LOG

  run cmd_stats --security
  assert_success
  assert_output --partial "3 detections"
  assert_output --partial "aws_key"
}

# ── Sessions Section ─────────────────────────────────────────

@test "stats shows no-backups message when backups dir empty" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats
  assert_success
  assert_output --partial "No transcript backups found."
}

@test "stats shows session backup count and size" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  mkdir -p "$CLAUDE_DIR/backups"
  echo '{"session": 1}' > "$CLAUDE_DIR/backups/session-001.jsonl"
  echo '{"session": 2}' > "$CLAUDE_DIR/backups/session-002.jsonl"
  echo '{"session": 3}' > "$CLAUDE_DIR/backups/session-003.jsonl"

  run cmd_stats
  assert_success
  assert_output --partial "3 transcripts"
  assert_output --partial "Disk usage"
}

@test "stats --sessions shows only sessions section" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --sessions
  assert_success
  assert_output --partial "Sessions"
  refute_output --partial "Installation"
  refute_output --partial "Security Events"
}

# ── Helper Functions ─────────────────────────────────────────

@test "format_bytes converts bytes to human-readable" {
  source "$SCRIPT_DIR/lib/platform.sh"

  run format_bytes 500
  assert_output "500 bytes"

  run format_bytes 2048
  assert_output "2.0 KB"

  run format_bytes 5242880
  assert_output "5.0 MB"

  run format_bytes 1073741824
  assert_output "1.0 GB"
}

@test "_stats_days_ago computes days from timestamp" {
  # Test with today's date
  local today
  today=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  run _stats_days_ago "$today"
  assert_output "today"
}
