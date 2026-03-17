#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests for forge ui CLI command
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/cmd-ui.sh"

  # Override open_browser to no-op in tests
  open_browser() { return 0; }
}

teardown() {
  # Kill any server we started
  if [ -f "$CLAUDE_DIR/forge-ui.pid" ]; then
    local pid
    pid=$(cat "$CLAUDE_DIR/forge-ui.pid" 2>/dev/null)
    kill "$pid" 2>/dev/null || true
    sleep 0.3
  fi
  teardown_sandbox
}

# ── Help ───────────────────────────────────────────────────────

@test "ui --help shows usage" {
  run cmd_ui --help
  assert_success
  assert_output --partial "forge ui"
  assert_output --partial "Start server"
  assert_output --partial "--port"
  assert_output --partial "--no-open"
}

@test "ui -h shows usage" {
  run cmd_ui -h
  assert_success
  assert_output --partial "forge ui"
}

# ── Node.js Check ─────────────────────────────────────────────

@test "ui fails with clear message when node is missing" {
  # Override command to simulate missing node
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "node" ]; then return 1; fi
    builtin command "$@"
  }

  run _ui_start 0 false
  assert_failure
  assert_output --partial "Node.js is required"
  assert_output --partial "https://nodejs.org"
}

# ── PID Management ────────────────────────────────────────────

@test "stale PID file is cleaned up" {
  # Write a PID that doesn't exist
  echo "99999999" > "$CLAUDE_DIR/forge-ui.pid"
  echo "12345" > "$CLAUDE_DIR/forge-ui.port"
  echo "token123" > "$CLAUDE_DIR/forge-ui.token"

  run _ui_read_running
  assert_failure

  # Files should be cleaned up
  assert [ ! -f "$CLAUDE_DIR/forge-ui.pid" ]
  assert [ ! -f "$CLAUDE_DIR/forge-ui.port" ]
  assert [ ! -f "$CLAUDE_DIR/forge-ui.token" ]
}

@test "cleanup removes all lifecycle files" {
  echo "123" > "$CLAUDE_DIR/forge-ui.pid"
  echo "8080" > "$CLAUDE_DIR/forge-ui.port"
  echo "abc" > "$CLAUDE_DIR/forge-ui.token"

  _ui_cleanup_stale

  assert [ ! -f "$CLAUDE_DIR/forge-ui.pid" ]
  assert [ ! -f "$CLAUDE_DIR/forge-ui.port" ]
  assert [ ! -f "$CLAUDE_DIR/forge-ui.token" ]
}

@test "read_running returns failure when no PID file" {
  run _ui_read_running
  assert_failure
}

# ── Stop Command ──────────────────────────────────────────────

@test "stop with no server running shows info message" {
  run _ui_stop
  assert_success
  assert_output --partial "No forge ui server is running"
}

# ── Status Command ────────────────────────────────────────────

@test "status with no server running shows not running" {
  run _ui_status
  assert_output --partial "No forge ui server is running"
  assert_output --partial "forge ui"
}

# ── Port Flag ─────────────────────────────────────────────────

@test "invalid port flag fails" {
  run cmd_ui --port
  assert_failure
  assert_output --partial "Missing value"
}

@test "non-numeric port fails" {
  run cmd_ui --port abc
  assert_failure
  assert_output --partial "Port must be a number"
}

# ── Unknown Options ───────────────────────────────────────────

@test "unknown option fails with help" {
  run cmd_ui --bogus
  assert_failure
  assert_output --partial "Unknown option"
}

# ── Server Start (requires node) ──────────────────────────────

@test "server starts and responds to health check" {
  if ! command -v node >/dev/null 2>&1; then
    skip "Node.js not available"
  fi

  # Start server with --no-open
  cmd_ui --no-open &
  local cmd_pid=$!

  # Wait for port file
  local waited=0
  while [ ! -f "$CLAUDE_DIR/forge-ui.port" ] && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  assert [ -f "$CLAUDE_DIR/forge-ui.port" ]
  assert [ -f "$CLAUDE_DIR/forge-ui.pid" ]
  assert [ -f "$CLAUDE_DIR/forge-ui.token" ]

  local port token
  port=$(cat "$CLAUDE_DIR/forge-ui.port")
  token=$(cat "$CLAUDE_DIR/forge-ui.token")

  # Health check
  run curl -s "http://127.0.0.1:${port}/api/health"
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial 'forge_version'

  # Status subcommand
  run _ui_status
  assert_output --partial "Server running"
  assert_output --partial "127.0.0.1"
}

@test "server rejects POST without token" {
  if ! command -v node >/dev/null 2>&1; then
    skip "Node.js not available"
  fi

  cmd_ui --no-open &
  local waited=0
  while [ ! -f "$CLAUDE_DIR/forge-ui.port" ] && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  local port
  port=$(cat "$CLAUDE_DIR/forge-ui.port")

  run curl -s -X POST "http://127.0.0.1:${port}/api/doctor"
  assert_success
  assert_output --partial '"ok":false'
  assert_output --partial 'token'
}

@test "server stop kills the process" {
  if ! command -v node >/dev/null 2>&1; then
    skip "Node.js not available"
  fi

  cmd_ui --no-open &
  local waited=0
  while [ ! -f "$CLAUDE_DIR/forge-ui.port" ] && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  assert [ -f "$CLAUDE_DIR/forge-ui.pid" ]

  run _ui_stop
  assert_success
  assert_output --partial "stopped"

  assert [ ! -f "$CLAUDE_DIR/forge-ui.pid" ]
}
