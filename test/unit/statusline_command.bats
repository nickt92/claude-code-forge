#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# statusline-command.sh — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  STATUSLINE="$SCRIPT_DIR/statusline-command.sh"
}

teardown() {
  teardown_sandbox
}

# Helper: run statusline with JSON input
run_sl() {
  echo "$1" | bash "$STATUSLINE"
}

# Minimal valid JSON — just model to pass validation
MINIMAL_JSON='{"model":{"id":"claude-sonnet-4-5","display_name":"Sonnet"},"workspace":{"current_dir":"/tmp"}}'

# ── Empty / Invalid Input ────────────────────────────────────

@test "empty input shows status message" {
  run bash -c 'echo "" | bash "$0"' "$STATUSLINE"
  assert_success
  assert_output --partial "statusline"
}

@test "invalid JSON shows waiting message" {
  run bash -c 'echo "not json" | bash "$0"' "$STATUSLINE"
  assert_success
  assert_output --partial "waiting"
}

# ── Valid JSON Output ────────────────────────────────────────

@test "valid input produces non-empty output" {
  run run_sl "$MINIMAL_JSON"
  assert_success
  [ -n "$output" ]
}

@test "output contains model name" {
  run run_sl "$MINIMAL_JSON"
  assert_success
  assert_output --partial "Sonnet"
}

@test "opus model shows Opus badge" {
  local json='{"model":{"id":"claude-opus-4-5","display_name":"Opus"},"workspace":{"current_dir":"/tmp"}}'
  run run_sl "$json"
  assert_success
  assert_output --partial "Opus"
}

@test "haiku model shows Haiku badge" {
  local json='{"model":{"id":"claude-haiku-4-5","display_name":"Haiku"},"workspace":{"current_dir":"/tmp"}}'
  run run_sl "$json"
  assert_success
  assert_output --partial "Haiku"
}

# ── Context Window ───────────────────────────────────────────

@test "context percentage clamps to 100" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "current_usage":{"input_tokens":250000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":-1
    }
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "100%"
}

@test "context percentage clamps to 0 for negative" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "current_usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":-1
    }
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "0%"
}

# ── Token Formatting ─────────────────────────────────────────

@test "shows token count with k suffix" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "current_usage":{"input_tokens":50000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":-1
    }
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "50k"
}

# ── Cost Display ─────────────────────────────────────────────

@test "shows cost when present" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "cost":{"total_cost_usd":2.50,"total_duration_ms":60000}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "$2.50"
}

# ── Rate Limits ──────────────────────────────────────────────

@test "shows rate limit when above threshold" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "rate_limits":{"five_hour":{"used_percentage":85,"resets_at":0}}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "85%"
}

# ── State File Path ──────────────────────────────────────────

@test "state file uses TMPDIR when set" {
  export TMPDIR="$TEST_SANDBOX/custom-tmp"
  mkdir -p "$TMPDIR"
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "session_id":"test-session-123",
    "context_window":{"total_output_tokens":100}
  }'
  run_sl "$json"
  # Check that state file was created in TMPDIR
  [ -f "$TMPDIR/forge-sl-test-session-123" ]
}

# ── Missing Fields ───────────────────────────────────────────

@test "handles missing cost gracefully" {
  run run_sl "$MINIMAL_JSON"
  assert_success
  # Should not crash, just not show cost
}

@test "handles missing context window gracefully" {
  run run_sl "$MINIMAL_JSON"
  assert_success
  # Should not crash
}

@test "handles missing rate limits gracefully" {
  run run_sl "$MINIMAL_JSON"
  assert_success
}
