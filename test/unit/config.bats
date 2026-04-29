#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests for forge config get/set
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-config.sh"
}

teardown() {
  teardown_sandbox
}

# ── forge config set ─────────────────────────────────────────

@test "config set creates forge-config.json if missing" {
  rm -f "$CLAUDE_DIR/forge-config.json"
  run _config_set "dashboard.scan_path" "/tmp/repos"
  assert_success
  assert [ -f "$CLAUDE_DIR/forge-config.json" ]
}

@test "config set stores string value at dotted path" {
  run _config_set "dashboard.scan_path" "/home/user/repos"
  assert_success
  local value
  value=$(jq -r '.dashboard.scan_path' "$CLAUDE_DIR/forge-config.json")
  assert_equal "$value" "/home/user/repos"
}

@test "config set stores numeric value as number" {
  run _config_set "dashboard.scan_depth" "3"
  assert_success
  local value
  value=$(jq -r '.dashboard.scan_depth' "$CLAUDE_DIR/forge-config.json")
  assert_equal "$value" "3"
  # Verify it's stored as a number, not string
  local type
  type=$(jq -r '.dashboard.scan_depth | type' "$CLAUDE_DIR/forge-config.json")
  assert_equal "$type" "number"
}

@test "config set overwrites existing value" {
  _config_set "dashboard.scan_path" "/old/path"
  run _config_set "dashboard.scan_path" "/new/path"
  assert_success
  local value
  value=$(jq -r '.dashboard.scan_path' "$CLAUDE_DIR/forge-config.json")
  assert_equal "$value" "/new/path"
}

@test "config set preserves other keys" {
  _config_set "dashboard.scan_path" "/repos"
  _config_set "dashboard.scan_depth" "5"
  run _config_set "dashboard.scan_path" "/other"
  assert_success
  local depth
  depth=$(jq -r '.dashboard.scan_depth' "$CLAUDE_DIR/forge-config.json")
  assert_equal "$depth" "5"
}

@test "config set fails without key" {
  run _config_set "" "value"
  assert_failure
  assert_output --partial "Usage"
}

@test "config set fails without value" {
  run _config_set "key" ""
  assert_failure
  assert_output --partial "Usage"
}

# ── forge config get ─────────────────────────────────────────

@test "config get reads existing value" {
  _config_set "dashboard.scan_path" "/repos"
  run _config_get "dashboard.scan_path"
  assert_success
  assert_output "/repos"
}

@test "config get fails for missing key" {
  _config_ensure_file
  run _config_get "nonexistent.key"
  assert_failure
  assert_output --partial "Key not set"
}

@test "config get fails without key argument" {
  run _config_get ""
  assert_failure
  assert_output --partial "Usage"
}

@test "config get creates config file if missing" {
  rm -f "$CLAUDE_DIR/forge-config.json"
  run _config_get "some.key"
  assert_failure
  assert [ -f "$CLAUDE_DIR/forge-config.json" ]
}

@test "config get reads numeric value" {
  _config_set "dashboard.scan_depth" "3"
  run _config_get "dashboard.scan_depth"
  assert_success
  assert_output "3"
}

# ── forge config list ────────────────────────────────────────

@test "config list shows empty message when no config" {
  _config_ensure_file
  run _config_list
  assert_success
  assert_output --partial "No configuration set"
}

@test "config list shows all settings" {
  _config_set "dashboard.scan_path" "/repos"
  _config_set "dashboard.scan_depth" "3"
  run _config_list
  assert_success
  assert_output --partial "dashboard.scan_path = /repos"
  assert_output --partial "dashboard.scan_depth = 3"
}

# ── forge config (entry point) ───────────────────────────────

@test "config with no subcommand shows help" {
  run cmd_config
  assert_success
  assert_output --partial "forge config"
  assert_output --partial "Usage"
}

@test "config --help shows help" {
  run cmd_config --help
  assert_success
  assert_output --partial "dashboard.scan_path"
}

@test "config unknown subcommand fails" {
  run cmd_config unknown
  assert_failure
  assert_output --partial "Unknown config subcommand"
}

# ── Key Validation ───────────────────────────────────────────

@test "config set rejects keys with special characters" {
  run _config_set "key; rm -rf" "value"
  assert_failure
}

@test "config set rejects keys with jq operators" {
  run _config_set "key | halt_error" "value"
  assert_failure
}

@test "config get rejects keys with special characters" {
  run _config_get "key; rm -rf"
  assert_failure
}

@test "config set handles values with spaces" {
  run _config_set "test.path" "/path with spaces/here"
  assert_success
  run _config_get "test.path"
  assert_success
  assert_output "/path with spaces/here"
}

@test "config set handles values with quotes" {
  run _config_set "test.val" 'has"quotes'
  assert_success
  run _config_get "test.val"
  assert_success
  assert_output 'has"quotes'
}

# ── Atomic write safety ─────────────────────────────────────

@test "config set uses atomic write (tmp + mv)" {
  _config_set "key" "value1"
  # Verify no .tmp file left behind
  assert [ ! -f "$CLAUDE_DIR/forge-config.json.tmp" ]
  # Verify file is valid JSON after write
  run jq '.' "$CLAUDE_DIR/forge-config.json"
  assert_success
}
