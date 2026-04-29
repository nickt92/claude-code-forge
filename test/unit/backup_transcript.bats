#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Backup Transcript Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/backup-transcript.sh"
}

teardown() {
  teardown_sandbox
}

# ── Copy Logic ───────────────────────────────────────────────

@test "copies transcript to backups directory" {
  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"abc123\",\"trigger\":\"PreCompact\"}" | bash "$HOOK"

  local backup_files
  backup_files=$(ls "$CLAUDE_DIR/backups/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  assert [ "$backup_files" -eq 1 ]
}

@test "backup filename includes session ID and trigger" {
  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"sess-42\",\"trigger\":\"PreCompact\"}" | bash "$HOOK"

  run ls "$CLAUDE_DIR/backups/"
  assert_output --partial "sess-42"
  assert_output --partial "PreCompact"
}

# ── Directory Creation ───────────────────────────────────────

@test "creates backups directory if missing" {
  rm -rf "$CLAUDE_DIR/backups"

  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"abc\",\"trigger\":\"test\"}" | bash "$HOOK"

  assert [ -d "$CLAUDE_DIR/backups" ]
}

# ── Missing Transcript ───────────────────────────────────────

@test "handles missing transcript file gracefully" {
  run bash -c 'echo "{\"transcript_path\":\"/nonexistent/file.jsonl\",\"session_id\":\"abc\",\"trigger\":\"test\"}" | bash "$0"' "$HOOK"
  assert_success
  # No backup created
  local count
  count=$(ls "$CLAUDE_DIR/backups/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  assert [ "$count" -eq 0 ]
}

# ── No auto-pruning (delegated to Claude Code cleanupPeriodDays) ──

# ── Path Traversal Sanitization ──────────────────────────────

@test "sanitizes path traversal characters in session ID" {
  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"../../etc/evil\",\"trigger\":\"test\"}" | bash "$HOOK"

  # Backup should land in backups dir, not traverse out
  local count
  count=$(ls "$CLAUDE_DIR/backups/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  assert [ "$count" -eq 1 ]

  # Filename should have slashes and dots replaced with underscores
  run ls "$CLAUDE_DIR/backups/"
  assert_output --partial "______etc_evil"
  refute_output --partial "../../"
}

@test "sanitizes special characters in trigger" {
  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"safe\",\"trigger\":\"pre/compact;rm -rf\"}" | bash "$HOOK"

  run ls "$CLAUDE_DIR/backups/"
  assert_output --partial "safe"
  refute_output --partial ";"
  refute_output --partial "/"
}

# ── No auto-pruning (delegated to Claude Code cleanupPeriodDays) ──

@test "does not prune old backups" {
  # Create an "old" backup
  local old_backup="$CLAUDE_DIR/backups/old-session-compact-20200101.jsonl"
  touch -t 202001010000 "$old_backup"

  # Create a fresh transcript
  local transcript="$TEST_SANDBOX/transcript.jsonl"
  echo '{"message":"test"}' > "$transcript"

  echo "{\"transcript_path\":\"$transcript\",\"session_id\":\"new\",\"trigger\":\"test\"}" | bash "$HOOK"

  # Old backup should still exist — cleanup is Claude Code's responsibility
  assert [ -f "$old_backup" ]
}
