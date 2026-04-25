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

@test "hides context segment when no data available" {
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
  # No percentage bar shown when no actual data
  refute_output --partial "◈"
}

@test "uses used_percentage directly from JSON" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "used_percentage":42,
      "current_usage":{"input_tokens":50000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":58
    }
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "42%"
}

@test "falls back to remaining_percentage when used_percentage absent" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "current_usage":{"input_tokens":50000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":70
    }
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "30%"
}

# ── Context bar without token counter (Option D) ────────────

@test "context shows bar and percentage but no raw token count" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "context_window":{
      "context_window_size":200000,
      "used_percentage":42,
      "current_usage":{"input_tokens":50000,"output_tokens":30000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
      "remaining_percentage":58
    }
  }'
  run run_sl "$json"
  assert_success
  # Bar and percentage should show
  assert_output --partial "42%"
  assert_output --partial "◈"
  # Raw token counter should NOT show (dropped in v1.3.0)
  refute_output --partial "50k"
  refute_output --partial "200k"
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
  assert_output --partial '$2.50'
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

# ── Effort Level ─────────────────────────────────────────────

@test "shows effort level when present" {
  local json='{
    "model":{"id":"claude-opus-4-5","display_name":"Opus"},
    "workspace":{"current_dir":"/tmp"},
    "effort":{"level":"high"}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "high"
}

@test "shows low effort level" {
  local json='{
    "model":{"id":"claude-sonnet-4-5","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "effort":{"level":"low"}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "low"
}

@test "handles missing effort level gracefully" {
  run run_sl "$MINIMAL_JSON"
  assert_success
}

# ── 7-Day Rate Limit ────────────────────────────────────────

@test "shows 7-day rate limit when above 50%" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "rate_limits":{"seven_day":{"used_percentage":75,"resets_at":0}}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "7d"
  assert_output --partial "75%"
}

@test "hides 7-day rate limit when below 50%" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "rate_limits":{"seven_day":{"used_percentage":30,"resets_at":0}}
  }'
  run run_sl "$json"
  assert_success
  refute_output --partial "7d"
}

# ── Session Name ─────────────────────────────────────────────

@test "shows session name when present" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "session_name":"my-feature-work"
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "my-feature-work"
}

@test "truncates long session names" {
  local json='{
    "model":{"id":"sonnet","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "session_name":"this-is-a-very-long-session-name-that-should-be-truncated"
  }'
  run run_sl "$json"
  assert_success
  # Should be truncated with ellipsis, not full name
  refute_output --partial "truncated"
  assert_output --partial "…"
}

# ── Worktree Detection ──────────────────────────────────────

@test "shows medium effort level" {
  local json='{
    "model":{"id":"claude-sonnet-4-5","display_name":"Sonnet"},
    "workspace":{"current_dir":"/tmp"},
    "effort":{"level":"medium"}
  }'
  run run_sl "$json"
  assert_success
  assert_output --partial "med"
}

@test "shows worktree icon via worktree.name fallback" {
  local repo="$TEST_SANDBOX/wt-fallback"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "init" -q

  local json
  json=$(jq -n --arg dir "$repo" '{
    "model":{"id":"claude-sonnet-4-5","display_name":"Sonnet"},
    "workspace":{"current_dir":$dir},
    "worktree":{"name":"feature-branch"}
  }')
  run run_sl "$json"
  assert_success
  assert_output --partial "🌲"
}

@test "shows worktree icon when workspace.git_worktree is true" {
  # Need a real git repo for the git zone to run worktree detection
  local repo="$TEST_SANDBOX/wt-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -m "init" -q

  local json
  json=$(jq -n --arg dir "$repo" '{
    "model":{"id":"claude-sonnet-4-5","display_name":"Sonnet"},
    "workspace":{"current_dir":$dir,"git_worktree":true}
  }')
  run run_sl "$json"
  assert_success
  assert_output --partial "🌲"
}
