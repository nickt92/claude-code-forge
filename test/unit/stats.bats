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

# ── Session Scorecard ────────────────────────────────────────

@test "stats --session shows no-events when log missing" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --session
  assert_success
  assert_output --partial "No session events"
}

@test "stats --session shows scorecard from session log" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  local session_log="${TMPDIR:-/tmp}/forge-session-log-${PPID}"
  cat > "$session_log" <<'LOG'
1700000000|session-init|5|allow
1700000001|architect-gate|2|allow
1700000002|command-guard|1|block
1700000003|architect-gate|3|allow
1700000004|secret-filter|4|detect
LOG

  run cmd_stats --session
  assert_success
  assert_output --partial "5"
  assert_output --partial "session-init"
  assert_output --partial "Blocked"
  rm -f "$session_log"
}

@test "stats --session shows only session section" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --session
  assert_success
  assert_output --partial "Session Scorecard"
  refute_output --partial "Installation"
}

# ── Hook Telemetry ──────────────────────────────────────────

@test "stats --hooks shows no-telemetry when log missing" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --hooks
  assert_success
  assert_output --partial "No hook telemetry"
}

@test "stats --hooks shows telemetry from log" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  local now
  now=$(date +%s)
  cat > "$CLAUDE_DIR/hook-telemetry.log" <<LOG
${now}|session-init|5|allow
${now}|architect-gate|10|allow
${now}|command-guard|3|block
${now}|architect-gate|8|allow
LOG

  run cmd_stats --hooks
  assert_success
  assert_output --partial "4"
  assert_output --partial "session-init"
  assert_output --partial "Block rate"
}

@test "stats --hooks shows only hooks section" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_stats --hooks
  assert_success
  assert_output --partial "Hook Telemetry"
  refute_output --partial "Installation"
}

@test "stats --hooks rotates entries older than 30 days" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  local now old_ts
  now=$(date +%s)
  old_ts=$(( now - 3000000 ))  # ~35 days ago

  cat > "$CLAUDE_DIR/hook-telemetry.log" <<LOG
${old_ts}|session-init|5|allow
${now}|architect-gate|10|allow
LOG

  run cmd_stats --hooks
  assert_success
  # After rotation, only 1 entry should remain
  local remaining
  remaining=$(wc -l < "$CLAUDE_DIR/hook-telemetry.log" | tr -d ' ')
  [ "$remaining" -eq 1 ]
}

@test "stats --hooks computes average duration" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  local now
  now=$(date +%s)
  cat > "$CLAUDE_DIR/hook-telemetry.log" <<LOG
${now}|hook-a|10|allow
${now}|hook-b|20|allow
LOG

  run cmd_stats --hooks
  assert_success
  assert_output --partial "15ms"
}

@test "stats --hooks shows block rate percentage" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  local now
  now=$(date +%s)
  cat > "$CLAUDE_DIR/hook-telemetry.log" <<LOG
${now}|a|1|allow
${now}|b|1|block
${now}|c|1|allow
${now}|d|1|allow
LOG

  run cmd_stats --hooks
  assert_success
  assert_output --partial "25%"
  assert_output --partial "1/4"
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
