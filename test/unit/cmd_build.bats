#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Build — unit tests for forge build non-interactive flags
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-build.sh"
}

teardown() {
  teardown_sandbox
}

build_args() {
  cmd_build --name "$1" \
    --communication technical --autonomy high \
    --workflow standard --depth practical "${@:2}"
}

@test "build --help shows non-interactive usage" {
  run cmd_build --help
  assert_success
  assert_output --partial "forge build"
  assert_output --partial "--communication"
}

@test "build with flags creates custom profile" {
  run build_args my-persona
  assert_success
  assert_file_exists "$CLAUDE_DIR/profiles/custom-my-persona.json"

  run jq -r '.persona' "$CLAUDE_DIR/profiles/custom-my-persona.json"
  assert_output "custom-my-persona"
  run jq -r '.axes.communication' "$CLAUDE_DIR/profiles/custom-my-persona.json"
  assert_output "technical"
  run jq -r '.default_plugin_group' "$CLAUDE_DIR/profiles/custom-my-persona.json"
  assert_output "full"
  run jq -r '.quality | length' "$CLAUDE_DIR/profiles/custom-my-persona.json"
  assert_output "1"
}

@test "build --quality engineering includes both quality tiers" {
  run build_args quality-persona --quality engineering
  assert_success
  run jq -r '.quality | join(",")' "$CLAUDE_DIR/profiles/custom-quality-persona.json"
  assert_output "core,engineering"
}

@test "build --plugins minimal is recorded in profile" {
  run build_args min-persona --plugins minimal
  assert_success
  run jq -r '.default_plugin_group' "$CLAUDE_DIR/profiles/custom-min-persona.json"
  assert_output "minimal"
}

@test "build rejects invalid name" {
  run cmd_build --name "9bad name" \
    --communication technical --autonomy high \
    --workflow standard --depth practical
  assert_failure
  assert_output --partial "Invalid name"
}

@test "build requires --name" {
  run cmd_build --communication technical --autonomy high \
    --workflow standard --depth practical
  assert_failure
  assert_output --partial "--name is required"
}

@test "build rejects builtin persona collision" {
  run build_args senior-engineer
  assert_failure
  assert_output --partial "built-in persona"
}

@test "build rejects invalid axis value" {
  run cmd_build --name axis-test \
    --communication shouty --autonomy high \
    --workflow standard --depth practical
  assert_failure
  assert_output --partial "--communication must be"
}

@test "build rejects invalid quality and plugins values" {
  run build_args q-test --quality luxury
  assert_failure
  assert_output --partial "--quality must be"

  run build_args p-test --plugins everything
  assert_failure
  assert_output --partial "--plugins must be"
}

@test "build fails on existing custom persona without --force" {
  run build_args dupe-persona
  assert_success

  run build_args dupe-persona
  assert_failure
  assert_output --partial "--force"
}

@test "build --force overwrites existing custom persona" {
  run build_args force-persona
  assert_success

  run cmd_build --name force-persona \
    --communication plain --autonomy guided \
    --workflow simplified --depth conceptual --force
  assert_success
  run jq -r '.axes.communication' "$CLAUDE_DIR/profiles/custom-force-persona.json"
  assert_output "plain"
}

@test "build rejects unknown option" {
  run cmd_build --bogus
  assert_failure
  assert_output --partial "Unknown option"
}

@test "build validates assembled output line count" {
  run build_args asm-persona
  assert_success
  assert_output --partial "lines when assembled"
}
