#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Init — integration tests for forge init
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/cmd-init.sh"

  # Set up global profile for default persona detection
  cp "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/profile.json"

  # Create a project directory to init in
  PROJECT_TEST_DIR="$TEST_SANDBOX/my-project"
  mkdir -p "$PROJECT_TEST_DIR"
}

teardown() {
  teardown_sandbox
}

@test "init creates .claude directory" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ -d "$PROJECT_TEST_DIR/.claude" ]
}

@test "init creates CLAUDE.md in project" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ -f "$PROJECT_TEST_DIR/.claude/CLAUDE.md" ]
}

@test "init creates rules in project" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ -d "$PROJECT_TEST_DIR/.claude/rules" ]
  # Check at least one rule exists
  local rule_count
  rule_count=$(ls "$PROJECT_TEST_DIR/.claude/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
  assert [ "$rule_count" -gt 0 ]
}

@test "init creates .gitignore" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ -f "$PROJECT_TEST_DIR/.claude/.gitignore" ]
}

@test "init does NOT modify global ~/.claude/" {
  cd "$PROJECT_TEST_DIR"
  local before_profile
  before_profile=$(cat "$CLAUDE_DIR/profile.json")

  run cmd_init --persona vibe-coder
  assert_success

  local after_profile
  after_profile=$(cat "$CLAUDE_DIR/profile.json")
  assert [ "$before_profile" = "$after_profile" ]
}

@test "init uses specified persona" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona vibe-coder
  assert_success
  run head -1 "$PROJECT_TEST_DIR/.claude/CLAUDE.md"
  assert_output --partial "vibe-coder"
}

@test "init uses global persona when none specified" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init
  assert_success
  run head -1 "$PROJECT_TEST_DIR/.claude/CLAUDE.md"
  assert_output --partial "senior-engineer"
}

@test "init fails for unknown persona" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona nonexistent-persona
  assert_failure
  assert_output --partial "Unknown persona"
}

@test "init --help shows usage" {
  run cmd_init --help
  assert_success
  assert_output --partial "Usage: forge init"
}

@test "init prints note about hooks being global" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_output --partial "Hooks and plugins are global"
}

@test "init does not create profile.json in project" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ ! -f "$PROJECT_TEST_DIR/.claude/profile.json" ]
}

@test "init does not create hooks in project" {
  cd "$PROJECT_TEST_DIR"
  run cmd_init --persona senior-engineer
  assert_success
  assert [ ! -d "$PROJECT_TEST_DIR/.claude/hooks" ]
}
