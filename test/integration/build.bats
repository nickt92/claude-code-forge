#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Build — integration tests for forge build
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests the profile generation logic (non-interactive parts).

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
}

teardown() {
  teardown_sandbox
}

@test "build --help shows usage" {
  source "$SCRIPT_DIR/lib/cmd-build.sh"
  run cmd_build --help
  assert_success
  assert_output --partial "Usage: forge build"
}

@test "custom profile with valid axes assembles correctly" {
  # Directly create a custom profile (simulating what build wizard does)
  cat > "$PROFILES_DIR/custom-test-build.json" <<'EOF'
{
  "schema_version": 1,
  "persona": "custom-test-build",
  "label": "Test Build (Custom)",
  "description": "Custom persona built with forge build",
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

  # Verify assembly works
  local temp_md
  temp_md="$(mktemp)"
  run assemble_claude_md "$PROFILES_DIR/custom-test-build.json" "$temp_md"
  assert_success

  # Clean up
  rm -f "$temp_md" "$PROFILES_DIR/custom-test-build.json"
}

@test "custom profile with engineering quality includes engineering section" {
  cat > "$PROFILES_DIR/custom-test-eng.json" <<'EOF'
{
  "schema_version": 1,
  "persona": "custom-test-eng",
  "label": "Test Eng (Custom)",
  "description": "Test custom persona",
  "axes": {
    "communication": "expert",
    "autonomy": "high",
    "workflow": "advanced",
    "depth": "engineering"
  },
  "quality": ["core", "engineering"],
  "default_plugin_group": "full"
}
EOF

  local temp_md
  temp_md="$(mktemp)"
  assemble_claude_md "$PROFILES_DIR/custom-test-eng.json" "$temp_md"

  # Should contain engineering quality content
  run grep -l "Testing" "$temp_md"
  assert_success

  rm -f "$temp_md" "$PROFILES_DIR/custom-test-eng.json"
}

@test "custom profile name validation rejects invalid names" {
  # Names starting with numbers should be rejected by the wizard
  # We test the regex directly
  [[ ! "123bad" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]
  [[ ! "" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]
  [[ ! "bad name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]
  [[ "good-name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]
  [[ "myTeam" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]
}

@test "custom profile axis mapping produces correct values" {
  # Verify the axis value arrays used by the wizard
  local comms=("plain" "technical" "expert")
  local autos=("guided" "moderate" "high")
  local works=("simplified" "standard" "advanced")
  local depths=("conceptual" "practical" "engineering")

  # Each value should have a corresponding section file
  for comm in "${comms[@]}"; do
    assert [ -f "$SECTIONS_DIR/communication-${comm}.md" ]
  done
  for auto in "${autos[@]}"; do
    assert [ -f "$SECTIONS_DIR/autonomy-${auto}.md" ]
  done
  for work in "${works[@]}"; do
    assert [ -f "$SECTIONS_DIR/workflow-${work}.md" ]
  done
  for depth in "${depths[@]}"; do
    assert [ -f "$SECTIONS_DIR/depth-${depth}.md" ]
  done
}
