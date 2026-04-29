#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Permissions — preset resolution, merge, unmerge, CLI output
# ━━━━━��━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  export FORGE_VERSION="1.2.1"
  source "$SCRIPT_DIR/lib/permissions-merge.sh"
  source "$SCRIPT_DIR/lib/manifest.sh"
}

teardown() {
  teardown_sandbox
}

# ── Preset resolution ────────────────────────────────────────

@test "resolve_preset_permissions returns tier 1 permissions" {
  run resolve_preset_permissions "ask-before-changes" "$SCRIPT_DIR/templates/permission-presets.json"
  assert_success

  # Should include Read, Glob, Grep
  echo "$output" | jq -e 'index("Read")' >/dev/null
  echo "$output" | jq -e 'index("Glob")' >/dev/null
  echo "$output" | jq -e 'index("Grep")' >/dev/null

  # Should include git read commands (moved to tier 1)
  echo "$output" | jq -e 'index("Bash(git status:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(git blame:*)")' >/dev/null

  # Should include system inspection commands
  echo "$output" | jq -e 'index("Bash(stat:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(jq:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(ps:*)")' >/dev/null

  # Should NOT include Write, Edit, or file manipulation
  run bash -c "echo '$output' | jq 'index(\"Write\")'"
  assert_output "null"
  run bash -c "echo '$output' | jq 'index(\"Bash(mkdir:*)\")'  "
  assert_output "null"
}

@test "resolve_preset_permissions resolves inheritance for auto-edit" {
  run resolve_preset_permissions "auto-edit" "$SCRIPT_DIR/templates/permission-presets.json"
  assert_success

  # Should include tier 1 + tier 2 permissions
  echo "$output" | jq -e 'index("Read")' >/dev/null
  echo "$output" | jq -e 'index("Write")' >/dev/null
  echo "$output" | jq -e 'index("Edit")' >/dev/null
  echo "$output" | jq -e 'index("Bash(git status:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(mkdir:*)")' >/dev/null
}

@test "resolve_preset_permissions resolves full chain for full-autonomy" {
  run resolve_preset_permissions "full-autonomy" "$SCRIPT_DIR/templates/permission-presets.json"
  assert_success

  # Should include all three tiers
  echo "$output" | jq -e 'index("Read")' >/dev/null
  echo "$output" | jq -e 'index("Write")' >/dev/null
  echo "$output" | jq -e 'index("Bash(mkdir:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(git commit:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(pytest:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(gh:*)")' >/dev/null
  echo "$output" | jq -e 'index("Bash(curl:*)")' >/dev/null
  echo "$output" | jq -e 'index("WebFetch")' >/dev/null
  echo "$output" | jq -e 'index("WebSearch")' >/dev/null
}

@test "resolve_preset_permissions returns empty for unknown preset" {
  run resolve_preset_permissions "nonexistent" "$SCRIPT_DIR/templates/permission-presets.json"
  assert_success
  assert_output "[]"
}

# ── Merge permissions ────────────────────────────────────────

@test "merge_permissions adds permissions to empty settings" {
  echo '{}' > "$CLAUDE_DIR/settings.json"

  merge_permissions "$CLAUDE_DIR/settings.json" "ask-before-changes" "$SCRIPT_DIR/templates/permission-presets.json"

  run jq '.permissions.allow | length' "$CLAUDE_DIR/settings.json"
  assert_success
  # Tier 1 has 36 permissions (3 built-in + 17 file/search + 6 system + 10 git)
  [ "$output" -ge 30 ]

  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  refute_output "null"
}

@test "merge_permissions preserves existing user permissions" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["CustomTool"]
  }
}
EOF

  merge_permissions "$CLAUDE_DIR/settings.json" "ask-before-changes" "$SCRIPT_DIR/templates/permission-presets.json"

  # Custom rule preserved
  run jq '.permissions.allow | index("CustomTool")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  # New rules added
  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  refute_output "null"
}

@test "merge_permissions deduplicates rules" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Read", "Glob"]
  }
}
EOF

  merge_permissions "$CLAUDE_DIR/settings.json" "ask-before-changes" "$SCRIPT_DIR/templates/permission-presets.json"

  # Read should appear exactly once
  run jq '[.permissions.allow[] | select(. == "Read")] | length' "$CLAUDE_DIR/settings.json"
  assert_output "1"
}

@test "merge_permissions never touches deny rules" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [],
    "deny": ["Bash(rm:*)"]
  }
}
EOF

  merge_permissions "$CLAUDE_DIR/settings.json" "auto-edit" "$SCRIPT_DIR/templates/permission-presets.json"

  run jq '.permissions.deny[0]' "$CLAUDE_DIR/settings.json"
  assert_output '"Bash(rm:*)"'
}

@test "merge_permissions creates settings file if missing" {
  merge_permissions "$CLAUDE_DIR/settings.json" "ask-before-changes" "$SCRIPT_DIR/templates/permission-presets.json"

  [ -f "$CLAUDE_DIR/settings.json" ]
  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  refute_output "null"
}

# ── Unmerge permissions ──────────────────────────────────────

@test "unmerge_permissions removes only specified rules" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep", "CustomTool", "Write"]
  }
}
EOF

  unmerge_permissions "$CLAUDE_DIR/settings.json" '["Read", "Glob", "Grep"]'

  # Removed
  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  assert_output "null"

  # Preserved
  run jq '.permissions.allow | index("CustomTool")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  run jq '.permissions.allow | index("Write")' "$CLAUDE_DIR/settings.json"
  refute_output "null"
}

@test "unmerge_permissions cleans up empty permissions object" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Read"]
  },
  "hooks": {}
}
EOF

  unmerge_permissions "$CLAUDE_DIR/settings.json" '["Read"]'

  # permissions key should be removed entirely
  run jq 'has("permissions")' "$CLAUDE_DIR/settings.json"
  assert_output "false"

  # Other keys preserved
  run jq 'has("hooks")' "$CLAUDE_DIR/settings.json"
  assert_output "true"
}

@test "unmerge_permissions preserves deny rules when cleaning up" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Read"],
    "deny": ["Bash(rm:*)"]
  }
}
EOF

  unmerge_permissions "$CLAUDE_DIR/settings.json" '["Read"]'

  # deny preserved, allow removed
  run jq '.permissions.deny[0]' "$CLAUDE_DIR/settings.json"
  assert_output '"Bash(rm:*)"'

  run jq 'has("permissions")' "$CLAUDE_DIR/settings.json"
  assert_output "true"
}

@test "unmerge_permissions no-op on missing file" {
  run unmerge_permissions "$CLAUDE_DIR/nonexistent.json" '["Read"]'
  assert_success
}

# ── CLI: forge permissions --list ────────────────────────────

@test "forge permissions --list --json returns valid JSON with 3 presets" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"
  local json_mode=true

  run _permissions_list
  assert_success

  echo "$output" | jq -e 'length == 3' >/dev/null
  echo "$output" | jq -e '.[0].id' >/dev/null
  echo "$output" | jq -e '.[0].label' >/dev/null
  echo "$output" | jq -e '.[0].tier' >/dev/null
  echo "$output" | jq -e '.[0].description' >/dev/null
}

@test "forge permissions --list --json presets are sorted by tier" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"
  local json_mode=true

  run _permissions_list
  assert_success

  echo "$output" | jq -e '.[0].tier == 1' >/dev/null
  echo "$output" | jq -e '.[1].tier == 2' >/dev/null
  echo "$output" | jq -e '.[2].tier == 3' >/dev/null
}

# ── CLI: forge permissions --preset ──────────────────────────

@test "forge permissions --preset auto-edit modifies settings" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"

  # Create manifest for tracking
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2,
  "forge_version": "1.2.1",
  "installed": {}
}
EOF

  echo '{}' > "$CLAUDE_DIR/settings.json"
  local json_mode=false

  run _permissions_apply "auto-edit"
  assert_success
  assert_output --partial "Auto-Edit"

  # Settings updated
  run jq '.permissions.allow | index("Write")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  # Manifest updated
  run jq -r '.installed.permissions_preset' "$MANIFEST_FILE"
  assert_output "auto-edit"
}

@test "forge permissions --preset downgrades cleanly" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"

  mkdir -p "$BACKUP_DIR"
  echo '{}' > "$CLAUDE_DIR/settings.json"

  # First apply auto-edit
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2,
  "forge_version": "1.2.1",
  "installed": {}
}
EOF
  local json_mode=false
  _permissions_apply "auto-edit"

  # Verify Write was added
  run jq '.permissions.allow | index("Write")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  # Now downgrade to ask-before-changes
  _permissions_apply "ask-before-changes"

  # Write should be removed
  run jq '.permissions.allow | index("Write")' "$CLAUDE_DIR/settings.json"
  assert_output "null"

  # Read should still be there
  run jq '.permissions.allow | index("Read")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  # Manifest updated
  run jq -r '.installed.permissions_preset' "$MANIFEST_FILE"
  assert_output "ask-before-changes"
}

@test "forge permissions --preset preserves custom user rules across changes" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"

  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2,
  "forge_version": "1.2.1",
  "installed": {}
}
EOF

  # Start with a custom rule
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["MyCustomTool"]
  }
}
EOF

  local json_mode=false
  _permissions_apply "auto-edit"

  # Custom rule survives
  run jq '.permissions.allow | index("MyCustomTool")' "$CLAUDE_DIR/settings.json"
  refute_output "null"

  # Switch preset
  _permissions_apply "ask-before-changes"

  # Custom rule still survives
  run jq '.permissions.allow | index("MyCustomTool")' "$CLAUDE_DIR/settings.json"
  refute_output "null"
}

@test "forge permissions --preset rejects unknown preset" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"

  local json_mode=false
  run _permissions_apply "bogus-preset"
  assert_failure
  assert_output --partial "Unknown preset"
}

# ── CLI: forge permissions (show) ────────────────────────────

@test "forge permissions --json shows current state" {
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/cmd-permissions.sh"

  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2,
  "forge_version": "1.2.1",
  "installed": {
    "permissions_preset": "auto-edit",
    "permissions_added": ["Read", "Write"]
  }
}
EOF

  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Read", "Write", "CustomTool"]
  }
}
EOF

  local json_mode=true
  run _permissions_show
  assert_success

  echo "$output" | jq -e '.currentPreset == "auto-edit"' >/dev/null
  echo "$output" | jq -e '.effectivePermissions | length == 3' >/dev/null
}
