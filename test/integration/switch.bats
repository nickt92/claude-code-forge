#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Switch — integration tests for forge switch
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  export FORGE_VERSION="1.1.0"
  source "$SCRIPT_DIR/lib/manifest.sh"
  source "$SCRIPT_DIR/lib/cmd-switch.sh"

  # Set up initial state: install as senior-engineer
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/CLAUDE.md"
  cp "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/profile.json"
  create_test_manifest_v2 "senior-engineer"
}

teardown() {
  teardown_sandbox
}

@test "switch changes CLAUDE.md to new persona" {
  local se_lines
  se_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')

  run cmd_switch "vibe-coder"
  assert_success

  local vc_lines
  vc_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
  assert [ "$se_lines" -ne "$vc_lines" ]
}

@test "switch updates profile.json" {
  cmd_switch "vibe-coder"
  run jq -r '.persona' "$CLAUDE_DIR/profile.json"
  assert_output "vibe-coder"
}

@test "switch updates manifest persona" {
  cmd_switch "vibe-coder"
  run jq -r '.persona' "$MANIFEST_FILE"
  assert_output "vibe-coder"
}

@test "switch prints success message" {
  run cmd_switch "vibe-coder"
  assert_success
  assert_output --partial "Switched to"
  assert_output --partial "Vibe Coder"
}

@test "switch fails for invalid persona" {
  run cmd_switch "nonexistent-persona"
  assert_failure
  assert_output --partial "Unknown persona"
}

@test "switch shows help with no args" {
  run cmd_switch
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "Available personas:"
}

@test "switch shows help with --help" {
  run cmd_switch --help
  assert_success
  assert_output --partial "Usage:"
}

@test "switch preserves CLAUDE.md header format" {
  cmd_switch "analyst"
  run head -1 "$CLAUDE_DIR/CLAUDE.md"
  assert_output --partial "Assembled by Claude Code Forge"
  assert_output --partial "analyst"
}
