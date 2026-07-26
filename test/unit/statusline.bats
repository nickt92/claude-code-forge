#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Statusline — unit tests for forge statusline legend
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-statusline.sh"
}

teardown() {
  teardown_sandbox
}

@test "statusline --help shows usage" {
  run cmd_statusline --help
  assert_success
  assert_output --partial "forge statusline"
  assert_output --partial "Usage"
}

@test "statusline with no args shows guide" {
  run cmd_statusline
  assert_success
  assert_output --partial "Statusline Guide"
}

@test "statusline shows all 5 zones" {
  run cmd_statusline
  assert_success
  assert_output --partial "Zone 1: Git"
  assert_output --partial "Zone 2: Model + Agent"
  assert_output --partial "Zone 3: Context Window"
  assert_output --partial "Zone 4: Limits + Speed"
  assert_output --partial "Zone 5: Session"
}

@test "statusline shows git icons" {
  run cmd_statusline
  assert_success
  assert_output --partial "Branch name"
  assert_output --partial "Worktree branch"
  assert_output --partial "Uncommitted changes"
  assert_output --partial "Commits ahead"
  assert_output --partial "Commits behind"
  assert_output --partial "Stash count"
}

@test "statusline shows model badges" {
  run cmd_statusline
  assert_success
  assert_output --partial "Opus model"
  assert_output --partial "Sonnet model"
  assert_output --partial "Haiku model"
  assert_output --partial "Active subagent"
}

@test "statusline shows context window info" {
  run cmd_statusline
  assert_success
  assert_output --partial "Context section"
  assert_output --partial "Gradient bar"
  assert_output --partial "Context used"
  assert_output --partial "Cache hit ratio"
}

@test "statusline shows limits and speed" {
  run cmd_statusline
  assert_success
  assert_output --partial "5-hour rate limit"
  assert_output --partial "7-day rate limit"
  assert_output --partial "Token speed"
}

@test "statusline shows session info" {
  run cmd_statusline
  assert_success
  assert_output --partial "Session name"
  assert_output --partial "Session cost"
  assert_output --partial "Lines added"
  assert_output --partial "Lines removed"
  assert_output --partial "Session duration"
  assert_output --partial "Vim mode"
}

@test "statusline shows color key" {
  run cmd_statusline
  assert_success
  assert_output --partial "Colors"
  assert_output --partial "Green"
  assert_output --partial "Yellow"
  assert_output --partial "Red"
  assert_output --partial "Bold"
}

@test "statusline shows example status line" {
  run cmd_statusline
  assert_success
  assert_output --partial "feat/thing"
  # The example renders context as a percentage, not raw token counts. It was
  # "124k/200k" before the statusline v8 redesign.
  assert_output --partial "62%"
}

@test "statusline rejects unknown options" {
  run cmd_statusline --foo
  assert_failure
  assert_output --partial "Unknown option"
}

@test "statusline works with NO_COLOR" {
  export NO_COLOR=1
  # Re-source ui.sh to pick up NO_COLOR
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-statusline.sh"
  run cmd_statusline
  assert_success
  assert_output --partial "Statusline Guide"
  assert_output --partial "Zone 1: Git"
  # Should not contain ANSI escape codes
  refute_output --partial $'\033['
}
