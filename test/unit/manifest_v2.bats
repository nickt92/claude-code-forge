#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Manifest v2 — migration, new fields, validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  export FORGE_VERSION="1.1.0"
  source "$SCRIPT_DIR/lib/manifest.sh"
}

teardown() {
  teardown_sandbox
}

# ── V1 to V2 Migration ──────────────────────────────────────

@test "migrate_v1_to_v2 upgrades manifest version" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 1,
  "forge_version": "1.0.0",
  "install_timestamp": "2025-01-01T00:00:00Z",
  "persona": "senior-engineer",
  "migrated_from_legacy": false,
  "pre_existing": {"files": {}, "directories": {}},
  "installed": {"files": [], "directories": {}, "settings_additions": {}}
}
EOF

  run manifest_migrate_v1_to_v2
  assert_success

  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "2"
}

@test "migrate_v1_to_v2 adds source_dir and plugin_group fields" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 1,
  "forge_version": "1.0.0",
  "install_timestamp": "2025-01-01T00:00:00Z",
  "persona": "senior-engineer",
  "migrated_from_legacy": false,
  "pre_existing": {"files": {}, "directories": {}},
  "installed": {"files": [], "directories": {}, "settings_additions": {}}
}
EOF

  manifest_migrate_v1_to_v2

  run jq -r '.source_dir // "null"' "$MANIFEST_FILE"
  assert_output "null"

  run jq -r '.plugin_group // "null"' "$MANIFEST_FILE"
  assert_output "null"
}

@test "migrate_v1_to_v2 preserves existing fields" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 1,
  "forge_version": "1.0.0",
  "persona": "vibe-coder",
  "migrated_from_legacy": true,
  "pre_existing": {"files": {"CLAUDE.md": {"backed_up": true}}, "directories": {}},
  "installed": {"files": ["CLAUDE.md"], "directories": {}, "settings_additions": {}}
}
EOF

  manifest_migrate_v1_to_v2

  run jq -r '.persona' "$MANIFEST_FILE"
  assert_output "vibe-coder"

  run jq -r '.migrated_from_legacy' "$MANIFEST_FILE"
  assert_output "true"

  run jq -r '.pre_existing.files["CLAUDE.md"].backed_up' "$MANIFEST_FILE"
  assert_output "true"
}

@test "migrate_v1_to_v2 is idempotent" {
  mkdir -p "$BACKUP_DIR"
  create_test_manifest_v2

  local before
  before=$(cat "$MANIFEST_FILE")

  run manifest_migrate_v1_to_v2
  assert_success

  local after
  after=$(cat "$MANIFEST_FILE")
  assert [ "$before" = "$after" ]
}

@test "migrate_v1_to_v2 is no-op when no manifest exists" {
  run manifest_migrate_v1_to_v2
  assert_success
}

# ── V2 Manifest Creation ────────────────────────────────────

@test "snapshot creates v2 manifest with source_dir and plugin_group" {
  snapshot_pre_install_state

  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "2"

  # source_dir and plugin_group start as null
  run jq -r '.source_dir // "null"' "$MANIFEST_FILE"
  assert_output "null"

  run jq -r '.plugin_group // "null"' "$MANIFEST_FILE"
  assert_output "null"
}

@test "update_manifest_installed sets source_dir and plugin_group" {
  snapshot_pre_install_state

  # Create minimal installed files
  touch "$CLAUDE_DIR/CLAUDE.md"
  echo '{}' > "$CLAUDE_DIR/settings.json"

  update_manifest_installed "senior-engineer" "/path/to/source" "full"

  run jq -r '.source_dir' "$MANIFEST_FILE"
  assert_output "/path/to/source"

  run jq -r '.plugin_group' "$MANIFEST_FILE"
  assert_output "full"
}

# ── Validation ───────────────────────────────────────────────

@test "validate_manifest accepts v2 manifest" {
  create_test_manifest_v2
  run validate_manifest
  assert_success
}

@test "validate_manifest accepts v1 manifest" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 1,
  "forge_version": "1.0.0",
  "persona": "test",
  "pre_existing": {},
  "installed": {}
}
EOF
  run validate_manifest
  assert_success
}

@test "validate_manifest rejects invalid version" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 99,
  "forge_version": "1.0.0",
  "persona": "test",
  "pre_existing": {},
  "installed": {}
}
EOF
  run validate_manifest
  assert_failure
}
