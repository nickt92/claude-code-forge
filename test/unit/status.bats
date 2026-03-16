#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Status — unit tests for forge status
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-status.sh"
}

teardown() {
  teardown_sandbox
}

@test "status --help shows usage" {
  run cmd_status --help
  assert_success
  assert_output --partial "forge status"
}

@test "status fails when not installed" {
  run cmd_status
  assert_failure
  assert_output --partial "not installed"
}

@test "status shows persona from profile.json" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  # Create minimal settings.json
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  assert_output --partial "senior-engineer"
}

@test "status shows plugin group from manifest" {
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {"a": true, "b": true}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  assert_output --partial "full"
}

@test "status shows version" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  # Manifest has 1.1.0, source has 1.2.0 — should show mismatch
  assert_output --partial "1.1.0"
  assert_output --partial "1.2.0"
}

@test "status shows matching version without mismatch note" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"
  # Update manifest to match source version
  local tmp
  tmp=$(jq '.forge_version = "1.2.0"' "$CLAUDE_DIR/forge-backup/manifest.json")
  echo "$tmp" > "$CLAUDE_DIR/forge-backup/manifest.json"

  run cmd_status
  assert_success
  assert_output --partial "1.2.0"
  refute_output --partial "source:"
}

@test "status shows hook count" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  # Install some hooks
  mkdir -p "$CLAUDE_DIR/hooks"
  for hook in architect-gate commit-validator session-init; do
    touch "$CLAUDE_DIR/hooks/${hook}.sh"
  done

  run cmd_status
  assert_success
  assert_output --partial "3 installed"
}

@test "status shows install timestamp" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  assert_output --partial "2026-01-01"
}

@test "status shows source directory" {
  create_test_manifest_v2 "senior-engineer" "/path/to/forge"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  assert_output --partial "/path/to/forge"
}

@test "status shows Status banner" {
  create_test_manifest_v2 "senior-engineer"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"

  run cmd_status
  assert_success
  assert_output --partial "Status"
}
