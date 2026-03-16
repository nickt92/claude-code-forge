#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Export — unit tests for forge export
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-export.sh"
}

teardown() {
  teardown_sandbox
}

# Helper: create a populated forge installation for export tests
_setup_exportable_install() {
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"
  echo "# Test CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  echo "#!/bin/bash" > "$CLAUDE_DIR/statusline-command.sh"

  mkdir -p "$CLAUDE_DIR/rules"
  echo "# rule 1" > "$CLAUDE_DIR/rules/quality.md"
  echo "# rule 2" > "$CLAUDE_DIR/rules/scope.md"

  mkdir -p "$CLAUDE_DIR/hooks"
  echo "#!/bin/bash" > "$CLAUDE_DIR/hooks/secret-filter.sh"

  mkdir -p "$CLAUDE_DIR/scripts"
  echo "#!/bin/bash" > "$CLAUDE_DIR/scripts/helper.sh"

  mkdir -p "$CLAUDE_DIR/lib"
  echo "# ui" > "$CLAUDE_DIR/lib/ui.sh"

  mkdir -p "$CLAUDE_DIR/completions"
  echo "# bash comp" > "$CLAUDE_DIR/completions/forge.bash"
  echo "# zsh comp" > "$CLAUDE_DIR/completions/forge.zsh"
}

# ── Help & Error Handling ────────────────────────────────────

@test "export --help shows usage" {
  run cmd_export --help
  assert_success
  assert_output --partial "forge export"
  assert_output --partial "no-custom-profiles"
}

@test "export fails when not installed" {
  run cmd_export
  assert_failure
  assert_output --partial "not installed"
}

# ── Archive Creation ─────────────────────────────────────────

@test "export creates tar.gz at default path" {
  _setup_exportable_install
  cd "$TEST_SANDBOX"

  run cmd_export
  assert_success
  assert_output --partial "Exported to"
  assert_output --partial ".tar.gz"

  # Verify archive exists
  local archive
  archive=$(ls forge-export-senior-engineer-*.tar.gz 2>/dev/null | head -1)
  [ -f "$archive" ]
}

@test "export -o uses custom path" {
  _setup_exportable_install
  local custom_path="$TEST_SANDBOX/custom-output.tar.gz"

  run cmd_export -o "$custom_path"
  assert_success
  assert_output --partial "Exported to $custom_path"
  [ -f "$custom_path" ]
}

@test "export archive contains forge-export-meta.json with correct fields" {
  _setup_exportable_install
  local archive_path="$TEST_SANDBOX/test-meta.tar.gz"

  run cmd_export -o "$archive_path"
  assert_success

  # Extract and check meta.json
  local extract_dir="$TEST_SANDBOX/extracted"
  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"

  local meta_file
  meta_file=$(find "$extract_dir" -name "forge-export-meta.json" | head -1)
  [ -f "$meta_file" ]

  # Verify fields
  run jq -r '.forge_version' "$meta_file"
  assert_output "1.1.0"

  run jq -r '.persona' "$meta_file"
  assert_output "senior-engineer"

  run jq -r '.plugin_group' "$meta_file"
  assert_output "full"

  run jq -r '.manifest_version' "$meta_file"
  assert_output "2"
}

@test "export archive contains profile.json, CLAUDE.md, rules, hooks" {
  _setup_exportable_install
  local archive_path="$TEST_SANDBOX/test-contents.tar.gz"

  run cmd_export -o "$archive_path"
  assert_success

  # List archive contents
  local contents
  contents=$(tar -tzf "$archive_path")

  echo "$contents" | grep -q "profile.json"
  echo "$contents" | grep -q "CLAUDE.md"
  echo "$contents" | grep -q "rules/"
  echo "$contents" | grep -q "hooks/"
}

@test "export archive does NOT contain settings.json" {
  _setup_exportable_install
  local archive_path="$TEST_SANDBOX/test-no-settings.tar.gz"

  run cmd_export -o "$archive_path"
  assert_success

  local contents
  contents=$(tar -tzf "$archive_path")
  ! echo "$contents" | grep -q "settings.json"
}

@test "export --no-custom-profiles excludes custom profiles" {
  _setup_exportable_install
  mkdir -p "$CLAUDE_DIR/profiles"
  echo '{"persona": "custom-one"}' > "$CLAUDE_DIR/profiles/custom-one.json"

  local archive_with="$TEST_SANDBOX/with-custom.tar.gz"
  local archive_without="$TEST_SANDBOX/without-custom.tar.gz"

  run cmd_export -o "$archive_with"
  assert_success
  local contents_with
  contents_with=$(tar -tzf "$archive_with")
  echo "$contents_with" | grep -q "profiles/custom-one.json"

  run cmd_export -o "$archive_without" --no-custom-profiles
  assert_success
  local contents_without
  contents_without=$(tar -tzf "$archive_without")
  ! echo "$contents_without" | grep -q "custom-one"
}

@test "export handles missing optional files gracefully" {
  # Minimal install — no completions, no custom profiles, no scripts
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
  create_test_profile "senior-engineer"
  echo '{"enabledPlugins": {}}' > "$CLAUDE_DIR/settings.json"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"

  local archive_path="$TEST_SANDBOX/test-minimal.tar.gz"

  run cmd_export -o "$archive_path"
  assert_success
  assert_output --partial "Exported to"
  [ -f "$archive_path" ]
}

@test "export archive contains forge-settings-additions.json when present" {
  _setup_exportable_install
  # Add settings_additions to manifest
  local tmp
  tmp=$(jq '.installed.settings_additions = {"hooks": {"Test": [{"matcher": ".*"}]}}' \
    "$CLAUDE_DIR/forge-backup/manifest.json")
  echo "$tmp" > "$CLAUDE_DIR/forge-backup/manifest.json"

  local archive_path="$TEST_SANDBOX/test-settings-additions.tar.gz"

  run cmd_export -o "$archive_path"
  assert_success

  local contents
  contents=$(tar -tzf "$archive_path")
  echo "$contents" | grep -q "forge-settings-additions.json"
}

@test "export displays profile name and file counts" {
  _setup_exportable_install

  run cmd_export -o "$TEST_SANDBOX/test-display.tar.gz"
  assert_success
  assert_output --partial "Test Profile"
  assert_output --partial "rules: 2 files"
  assert_output --partial "hooks: 1 files"
}
