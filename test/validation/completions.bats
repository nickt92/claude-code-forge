#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Completions — validation tests for shell completion scripts
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "bash completion script exists" {
  assert [ -f "$SCRIPT_DIR/completions/forge.bash" ]
}

@test "zsh completion script exists" {
  assert [ -f "$SCRIPT_DIR/completions/forge.zsh" ]
}

@test "bash completion is valid bash syntax" {
  run bash -n "$SCRIPT_DIR/completions/forge.bash"
  assert_success
}

@test "zsh completion is valid zsh syntax" {
  # zsh -n checks syntax without executing
  if command -v zsh >/dev/null 2>&1; then
    run zsh -n "$SCRIPT_DIR/completions/forge.zsh"
    assert_success
  else
    skip "zsh not available"
  fi
}

@test "bash completion defines _forge function" {
  run grep -c '_forge()' "$SCRIPT_DIR/completions/forge.bash"
  assert_success
  assert_output "1"
}

@test "bash completion registers with complete command" {
  run grep 'complete -F _forge forge' "$SCRIPT_DIR/completions/forge.bash"
  assert_success
}

@test "bash completion includes all subcommands" {
  local content
  content=$(cat "$SCRIPT_DIR/completions/forge.bash")
  for cmd in build diff doctor help init install status switch update version; do
    echo "$content" | grep -q "$cmd" || fail "Missing subcommand: $cmd"
  done
}

@test "zsh completion includes all subcommands" {
  local content
  content=$(cat "$SCRIPT_DIR/completions/forge.zsh")
  for cmd in build diff doctor help init install status switch update version; do
    echo "$content" | grep -q "$cmd" || fail "Missing subcommand: $cmd"
  done
}
