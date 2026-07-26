#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Update — integration tests for forge update
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests update logic with mocked git operations.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  export FORGE_VERSION="1.1.0"
  source "$SCRIPT_DIR/lib/manifest.sh"

  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
}

teardown() {
  teardown_sandbox
}

@test "update --help shows usage" {
  source "$SCRIPT_DIR/lib/cmd-update.sh"
  run cmd_update --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "forge update"
}

@test "update fails when source dir is not a git repo" {
  # Use a temp dir that's not a git repo
  export FORGE_SOURCE_DIR="$TEST_SANDBOX/not-a-repo"
  mkdir -p "$FORGE_SOURCE_DIR"
  source "$SCRIPT_DIR/lib/cmd-update.sh"
  run cmd_update
  assert_failure
  assert_output --partial "not a git repository"
}

@test "update fails when source dir has uncommitted changes" {
  # Create a git repo with dirty state
  local repo="$TEST_SANDBOX/dirty-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  echo "file" > "$repo/test.txt"
  git -C "$repo" add test.txt
  git -C "$repo" commit -q -m "init"
  echo "dirty" >> "$repo/test.txt"

  export FORGE_SOURCE_DIR="$repo"
  source "$SCRIPT_DIR/lib/cmd-update.sh"
  run cmd_update
  assert_failure
  assert_output --partial "uncommitted changes"
}
