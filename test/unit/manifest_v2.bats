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

@test "snapshot creates a current-version manifest with source_dir and plugin_group" {
  snapshot_pre_install_state

  # Derived, not pinned — snapshot writes whatever MANIFEST_VERSION currently is.
  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "$MANIFEST_VERSION"

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

# ── Permissions ownership record ─────────────────────────────
# update_manifest_installed rewrites .installed wholesale. The permissions
# ownership record lives under .installed, and only the --permissions branch of
# install rewrites it afterwards. `forge update` reinstalls WITHOUT that flag,
# so without these guards the record is erased on every update — after which
# the removal step is skipped and merge_permissions (a pure union) can only
# ever add rules. That is a one-way ratchet: presets stop being switchable and
# a deny list, once shipped, could never be withdrawn.

@test "update_manifest_installed preserves the permissions ownership record" {
  snapshot_pre_install_state
  touch "$CLAUDE_DIR/CLAUDE.md"
  echo '{}' > "$CLAUDE_DIR/settings.json"

  jq '.installed.permissions = {
        schema: 1, preset: "full-autonomy", provenance: "native",
        owned: { allow: ["Bash(npm:*)"] }, adopted: { allow: ["Read"] }
      }' "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
  mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

  update_manifest_installed "senior-engineer" "/path/to/source" "full"

  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "full-autonomy"
  run jq -c '.installed.permissions.owned.allow' "$MANIFEST_FILE"
  assert_output '["Bash(npm:*)"]'
  run jq -c '.installed.permissions.adopted.allow' "$MANIFEST_FILE"
  assert_output '["Read"]'
}

@test "update_manifest_installed leaves the permissions key absent when never set" {
  snapshot_pre_install_state
  touch "$CLAUDE_DIR/CLAUDE.md"
  echo '{}' > "$CLAUDE_DIR/settings.json"

  update_manifest_installed "senior-engineer" "/path/to/source" "full"

  # Absent, not null — an explicit null would satisfy `// "none"` fallbacks but
  # would misreport "forge has a record of no preset" in --json output.
  run jq -r '.installed | has("permissions")' "$MANIFEST_FILE"
  assert_output "false"
}

# ── v2 to v3 migration ───────────────────────────────────────

@test "migrate_v2_to_v3 splits the old flat record into owned and adopted" {
  mkdir -p "$BACKUP_DIR"
  # The user still has Read; Bash(npm:*) was removed from settings since.
  echo '{"permissions":{"allow":["Read","Bash(mytool:*)"]}}' > "$CLAUDE_DIR/settings.json"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2,
  "forge_version": "1.4.0",
  "persona": "senior-engineer",
  "pre_existing": {"files": {}, "directories": {}},
  "installed": {
    "files": [], "directories": {}, "settings_additions": {},
    "permissions_preset": "auto-edit",
    "permissions_added": ["Read", "Bash(npm:*)"]
  }
}
EOF
  run manifest_migrate_v2_to_v3
  assert_success

  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "3"
  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "auto-edit"
  # Only entries still present in settings are claimed; the rest are dropped
  # rather than resurrected as forge's.
  run jq -c '.installed.permissions.owned.allow' "$MANIFEST_FILE"
  assert_output '["Read"]'
  # v2 cannot distinguish adopted from owned, so the imprecision is marked.
  run jq -r '.installed.permissions.provenance' "$MANIFEST_FILE"
  assert_output "migrated"
  run jq -r '.installed | has("permissions_added")' "$MANIFEST_FILE"
  assert_output "false"
}

@test "migrate_v2_to_v3 is idempotent" {
  mkdir -p "$BACKUP_DIR"
  echo '{"permissions":{"allow":["Read"]}}' > "$CLAUDE_DIR/settings.json"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2, "forge_version": "1.4.0", "persona": "x",
  "pre_existing": {}, "installed": {"permissions_preset": "auto-edit", "permissions_added": ["Read"]}
}
EOF
  manifest_migrate_v2_to_v3
  local first
  first=$(cat "$MANIFEST_FILE")
  manifest_migrate_v2_to_v3
  assert_equal "$(cat "$MANIFEST_FILE")" "$first"
}

@test "migrate_v2_to_v3 is a no-op on a manifest with no preset recorded" {
  mkdir -p "$BACKUP_DIR"
  cat > "$MANIFEST_FILE" <<'EOF'
{
  "manifest_version": 2, "forge_version": "1.4.0", "persona": "x",
  "pre_existing": {}, "installed": {"files": [], "directories": {}}
}
EOF
  run manifest_migrate_v2_to_v3
  assert_success
  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "3"
  run jq -r '.installed | has("permissions")' "$MANIFEST_FILE"
  assert_output "false"
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
