#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Forge CLI — unit tests for the forge dispatcher
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
}

teardown() {
  teardown_sandbox
}

# ── Version ──────────────────────────────────────────────────

@test "forge version prints version number" {
  run "$SCRIPT_DIR/forge" version
  assert_success
  assert_output --partial "forge"
  assert_output --partial "1.2.1"
}

@test "forge --version prints version number" {
  run "$SCRIPT_DIR/forge" --version
  assert_success
  assert_output --partial "forge"
}

@test "forge -v prints version number" {
  run "$SCRIPT_DIR/forge" -v
  assert_success
  assert_output --partial "forge"
}

# ── Help ─────────────────────────────────────────────────────

@test "forge help prints usage info" {
  run "$SCRIPT_DIR/forge" help
  assert_success
  assert_output --partial "Setup"
  assert_output --partial "install"
  assert_output --partial "switch"
  assert_output --partial "doctor"
}

@test "forge --help prints usage info" {
  run "$SCRIPT_DIR/forge" --help
  assert_success
  assert_output --partial "Setup"
}

@test "forge with no args shows help" {
  run "$SCRIPT_DIR/forge"
  assert_success
  assert_output --partial "Setup"
}

# ── Unknown command ──────────────────────────────────────────

@test "forge unknown-cmd fails with error" {
  run "$SCRIPT_DIR/forge" nonexistent-command
  assert_failure
  assert_output --partial "Unknown command"
  assert_output --partial "Available commands:"
}

# ── Command discovery ────────────────────────────────────────

@test "forge lists available commands on unknown input" {
  run "$SCRIPT_DIR/forge" bogus
  assert_failure
  assert_output --partial "install"
  assert_output --partial "switch"
  assert_output --partial "doctor"
}
