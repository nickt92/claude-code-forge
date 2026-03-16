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

@test "switch finds custom profile in user space" {
  # Create a custom profile in user-space profiles dir
  mkdir -p "$CLAUDE_DIR/profiles"
  cat > "$CLAUDE_DIR/profiles/custom-user-test.json" <<'EOF'
{
  "schema_version": 1,
  "persona": "custom-user-test",
  "label": "User Test (Custom)",
  "description": "Custom persona in user space",
  "axes": {
    "communication": "technical",
    "autonomy": "moderate",
    "workflow": "standard",
    "depth": "practical"
  },
  "quality": ["core"],
  "default_plugin_group": "standard"
}
EOF

  run cmd_switch "custom-user-test"
  assert_success
  assert_output --partial "Switched to"

  run jq -r '.persona' "$CLAUDE_DIR/profile.json"
  assert_output "custom-user-test"
}

@test "switch help lists user-space custom profiles" {
  mkdir -p "$CLAUDE_DIR/profiles"
  cat > "$CLAUDE_DIR/profiles/custom-listed.json" <<'EOF'
{
  "schema_version": 1,
  "persona": "custom-listed",
  "label": "Listed (Custom)",
  "description": "Test listing",
  "axes": { "communication": "plain", "autonomy": "guided", "workflow": "simplified", "depth": "conceptual" },
  "quality": ["core"],
  "default_plugin_group": "minimal"
}
EOF

  run cmd_switch --help
  assert_success
  assert_output --partial "custom-listed"
}
