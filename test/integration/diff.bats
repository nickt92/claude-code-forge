#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Diff — integration tests for forge diff
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  source "$SCRIPT_DIR/lib/plugins.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  export FORGE_VERSION="1.1.0"
  source "$SCRIPT_DIR/lib/manifest.sh"
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"

  # Set up a clean install state
  _setup_clean_install
}

teardown() {
  teardown_sandbox
}

_setup_clean_install() {
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/CLAUDE.md"
  cp "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/profile.json"

  for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
    cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  done
  for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
    cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  done
  mkdir -p "$CLAUDE_DIR/scripts"
  for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
    [ -f "$script_file" ] && cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
  done
  cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  mkdir -p "$CLAUDE_DIR/lib"
  cp "$SCRIPT_DIR/lib/ui.sh" "$CLAUDE_DIR/lib/ui.sh"
  cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
}

@test "diff shows no differences on clean install" {
  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff
  assert_success
  assert_output --partial "No differences found"
}

@test "diff detects modified rule" {
  echo "# modified" >> "$CLAUDE_DIR/rules/scope-discipline.md"
  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff
  assert_output --partial "scope-discipline.md"
}

@test "diff detects missing hook" {
  rm -f "$CLAUDE_DIR/hooks/session-init.sh"
  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff
  assert_output --partial "session-init.sh (new in source)"
}

@test "diff detects version mismatch" {
  local tmp="${MANIFEST_FILE}.tmp"
  jq '.forge_version = "0.9.0"' "$MANIFEST_FILE" > "$tmp"
  mv "$tmp" "$MANIFEST_FILE"

  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff
  assert_output --partial "Version"
  assert_output --partial "installed=0.9.0"
}

@test "diff --help shows usage" {
  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "forge diff"
}

@test "diff detects CLAUDE.md drift" {
  echo "# extra content" >> "$CLAUDE_DIR/CLAUDE.md"
  source "$SCRIPT_DIR/lib/cmd-diff.sh"
  run cmd_diff
  assert_output --partial "CLAUDE.md"
}
