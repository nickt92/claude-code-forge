#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Doctor — integration tests for forge doctor
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/settings-merge.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/plugins.sh"
  export FORGE_VERSION="1.1.0"
  source "$SCRIPT_DIR/lib/manifest.sh"

  export FORGE_SOURCE_DIR="$SCRIPT_DIR"

  # Simulate a healthy install
  _setup_healthy_install
}

teardown() {
  teardown_sandbox
}

_setup_healthy_install() {
  # CLAUDE.md + profile
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/CLAUDE.md"
  cp "$PROFILES_DIR/senior-engineer.json" "$CLAUDE_DIR/profile.json"

  # Rules
  for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
    cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  done

  # Hooks
  for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
    cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  done

  # Scripts
  mkdir -p "$CLAUDE_DIR/scripts"
  for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
    [ -f "$script_file" ] && cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    [ -f "$script_file" ] && chmod +x "$CLAUDE_DIR/scripts/$(basename "$script_file")"
  done

  # Status line
  cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"

  # Lib files
  mkdir -p "$CLAUDE_DIR/lib"
  cp "$SCRIPT_DIR/lib/ui.sh" "$CLAUDE_DIR/lib/ui.sh"

  # Settings
  cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"

  # Forge symlink
  mkdir -p "$CLAUDE_DIR/bin"
  ln -sf "$SCRIPT_DIR/forge" "$CLAUDE_DIR/bin/forge"

  # Manifest
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
}

@test "doctor passes on healthy install" {
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_success
  assert_output --partial "checks passed"
}

@test "doctor detects missing rules file" {
  rm -f "$CLAUDE_DIR/rules/scope-discipline.md"
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_failure
  assert_output --partial "Missing: rules/scope-discipline.md"
}

@test "doctor detects modified hook" {
  echo "# modified" >> "$CLAUDE_DIR/hooks/session-init.sh"
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_success  # modified = warning, not failure
  assert_output --partial "Modified: hooks/session-init.sh"
}

@test "doctor detects stale CLAUDE.md" {
  echo "# extra line that makes it differ" >> "$CLAUDE_DIR/CLAUDE.md"
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_output --partial "differs from current profile"
}

@test "doctor detects version mismatch" {
  local tmp="${MANIFEST_FILE}.tmp"
  jq '.forge_version = "0.9.0"' "$MANIFEST_FILE" > "$tmp"
  mv "$tmp" "$MANIFEST_FILE"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_output --partial "Version mismatch"
}

@test "doctor detects missing manifest" {
  rm -f "$MANIFEST_FILE"
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_failure
  assert_output --partial "No manifest found"
}

@test "doctor checks forge symlink" {
  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  run cmd_doctor
  assert_output --partial "forge symlink OK"
}

# ── Project Context ──────────────────────────────────────────

@test "doctor shows project context when .claude/ exists in cwd" {
  # Create a project dir with .claude/
  local project_dir="$TEST_SANDBOX/my-project"
  mkdir -p "$project_dir/.claude"
  touch "$project_dir/.claude/CLAUDE.md"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  cd "$project_dir"
  run cmd_doctor
  assert_output --partial "Project Context"
  assert_output --partial "CLAUDE.md present"
}

@test "doctor shows missing document chain files" {
  local project_dir="$TEST_SANDBOX/my-project"
  mkdir -p "$project_dir/.claude"
  touch "$project_dir/.claude/CLAUDE.md"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  cd "$project_dir"
  run cmd_doctor
  assert_output --partial "No PROJECT.md"
  assert_output --partial "No REQUIREMENTS.md"
  assert_output --partial "No ROADMAP.md"
}

@test "doctor shows existing document chain files as OK" {
  local project_dir="$TEST_SANDBOX/my-project"
  mkdir -p "$project_dir/.claude"
  touch "$project_dir/.claude/CLAUDE.md"
  touch "$project_dir/PROJECT.md"
  touch "$project_dir/ROADMAP.md"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  cd "$project_dir"
  run cmd_doctor
  assert_output --partial "PROJECT.md"
  assert_output --partial "ROADMAP.md"
  assert_output --partial "No REQUIREMENTS.md"
}

@test "doctor respects docchain-skip marker" {
  local project_dir="$TEST_SANDBOX/my-project"
  mkdir -p "$project_dir/.claude"
  touch "$project_dir/.claude/.docchain-skip"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  cd "$project_dir"
  run cmd_doctor
  assert_output --partial "dismissed"
  refute_output --partial "No PROJECT.md"
}

@test "doctor skips project context when no .claude/ in cwd" {
  local project_dir="$TEST_SANDBOX/no-forge-project"
  mkdir -p "$project_dir"

  source "$SCRIPT_DIR/lib/cmd-doctor.sh"
  cd "$project_dir"
  run cmd_doctor
  refute_output --partial "Project Context"
}
