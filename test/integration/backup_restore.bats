#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Backup & Restore — integration tests for manifest-based system
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/settings-merge.sh"

  export FORGE_VERSION="0.1.0-test"
  source "$SCRIPT_DIR/lib/backup.sh"
}

teardown() {
  teardown_sandbox
}

# ── Snapshot ─────────────────────────────────────────────────

@test "snapshot creates forge-backup/ and manifest.json" {
  snapshot_pre_install_state
  assert [ -d "$BACKUP_DIR" ]
  assert [ -f "$MANIFEST_FILE" ]
}

@test "snapshot records manifest_version and forge_version" {
  snapshot_pre_install_state
  run jq -r '.manifest_version' "$MANIFEST_FILE"
  assert_output "1"
  run jq -r '.forge_version' "$MANIFEST_FILE"
  assert_output "0.1.0-test"
}

@test "snapshot copies existing CLAUDE.md to forge-backup/" {
  echo "my custom config" > "$CLAUDE_DIR/CLAUDE.md"
  snapshot_pre_install_state

  assert [ -f "$BACKUP_DIR/CLAUDE.md" ]
  run cat "$BACKUP_DIR/CLAUDE.md"
  assert_output "my custom config"
}

@test "snapshot copies existing settings.json to forge-backup/" {
  echo '{"custom":"yes"}' > "$CLAUDE_DIR/settings.json"
  snapshot_pre_install_state

  assert [ -f "$BACKUP_DIR/settings.json" ]
  run jq -r '.custom' "$BACKUP_DIR/settings.json"
  assert_output "yes"
}

@test "snapshot records pre-existing file inventory in manifest" {
  echo "content" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{}' > "$CLAUDE_DIR/settings.json"
  snapshot_pre_install_state

  run jq -r '.pre_existing.files["CLAUDE.md"].backed_up' "$MANIFEST_FILE"
  assert_output "true"
  run jq -r '.pre_existing.files["settings.json"].backed_up' "$MANIFEST_FILE"
  assert_output "true"
}

@test "snapshot copies existing rules directory files" {
  mkdir -p "$CLAUDE_DIR/rules"
  echo "my rule" > "$CLAUDE_DIR/rules/my-custom-rule.md"
  snapshot_pre_install_state

  assert [ -f "$BACKUP_DIR/rules/my-custom-rule.md" ]
  run cat "$BACKUP_DIR/rules/my-custom-rule.md"
  assert_output "my rule"
}

@test "snapshot records pre-existing directory file list" {
  mkdir -p "$CLAUDE_DIR/rules"
  echo "rule1" > "$CLAUDE_DIR/rules/custom-a.md"
  echo "rule2" > "$CLAUDE_DIR/rules/custom-b.md"
  snapshot_pre_install_state

  run jq -r '.pre_existing.directories.rules.files | sort | .[]' "$MANIFEST_FILE"
  assert_line --index 0 "custom-a.md"
  assert_line --index 1 "custom-b.md"
}

@test "snapshot skipped on re-install (backup preserved)" {
  echo "original" > "$CLAUDE_DIR/CLAUDE.md"
  snapshot_pre_install_state

  # Overwrite CLAUDE.md (simulating install)
  echo "forge version" > "$CLAUDE_DIR/CLAUDE.md"

  # Second snapshot should be a no-op
  snapshot_pre_install_state

  # Backup should still have original content
  run cat "$BACKUP_DIR/CLAUDE.md"
  assert_output "original"
}

@test "snapshot handles empty CLAUDE_DIR gracefully" {
  # Remove the pre-created directories from sandbox setup
  rm -rf "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/backups" "$CLAUDE_DIR/plans"
  snapshot_pre_install_state

  run jq '.pre_existing.files | length' "$MANIFEST_FILE"
  assert_output "0"
  run jq '.pre_existing.directories | length' "$MANIFEST_FILE"
  assert_output "0"
}

# ── Update Manifest Installed ────────────────────────────────

@test "update_manifest_installed records installed files" {
  snapshot_pre_install_state

  # Simulate forge installing files
  echo "forge claude" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"persona":"senior"}' > "$CLAUDE_DIR/profile.json"
  cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"

  update_manifest_installed "senior-engineer"

  run jq -r '.installed.files | sort | .[]' "$MANIFEST_FILE"
  assert_line --index 0 "CLAUDE.md"
  assert_line --index 1 "profile.json"
  assert_line --index 2 "statusline-command.sh"
}

@test "update_manifest_installed records installed directory files" {
  snapshot_pre_install_state

  # Simulate forge installing rules
  mkdir -p "$CLAUDE_DIR/rules"
  echo "rule" > "$CLAUDE_DIR/rules/agent-orchestration.md"
  echo "rule" > "$CLAUDE_DIR/rules/commit-and-delivery.md"

  update_manifest_installed "senior-engineer"

  run jq -r '.installed.directories.rules | sort | .[]' "$MANIFEST_FILE"
  assert_line --index 0 "agent-orchestration.md"
  assert_line --index 1 "commit-and-delivery.md"
}

@test "update_manifest_installed captures settings diff" {
  # Pre-existing settings
  echo '{"custom":"setting"}' > "$CLAUDE_DIR/settings.json"
  snapshot_pre_install_state

  # After merge, settings has forge additions
  echo '{"custom":"setting","statusLine":{"type":"command"},"alwaysThinkingEnabled":true}' > "$CLAUDE_DIR/settings.json"

  update_manifest_installed "senior-engineer"

  run jq -r '.installed.settings_additions.statusLine.type' "$MANIFEST_FILE"
  assert_output "command"
}

@test "update_manifest_installed sets persona" {
  snapshot_pre_install_state
  update_manifest_installed "vibe-coder"

  run jq -r '.persona' "$MANIFEST_FILE"
  assert_output "vibe-coder"
}

# ── Legacy Migration ─────────────────────────────────────────

@test "migrate_legacy_backups moves oldest backup to forge-backup/" {
  # Create legacy backup files
  echo "old config" > "$CLAUDE_DIR/CLAUDE.md.backup-20240101-120000"
  echo "newer config" > "$CLAUDE_DIR/CLAUDE.md.backup-20240601-120000"

  snapshot_pre_install_state
  migrate_legacy_backups

  # Oldest should be in forge-backup/ (first one found by glob)
  assert [ -f "$BACKUP_DIR/CLAUDE.md" ]

  # Legacy files should be cleaned up
  assert [ ! -f "$CLAUDE_DIR/CLAUDE.md.backup-20240101-120000" ]
  assert [ ! -f "$CLAUDE_DIR/CLAUDE.md.backup-20240601-120000" ]
}

@test "migrate_legacy_backups sets migrated flag" {
  echo "old" > "$CLAUDE_DIR/settings.json.backup-20240101-000000"
  snapshot_pre_install_state
  migrate_legacy_backups

  run jq -r '.migrated_from_legacy' "$MANIFEST_FILE"
  assert_output "true"
}

@test "migrate_legacy_backups is idempotent" {
  echo "old" > "$CLAUDE_DIR/CLAUDE.md.backup-20240101-000000"
  snapshot_pre_install_state
  migrate_legacy_backups

  # Running again should be a no-op (flag check)
  run migrate_legacy_backups
  assert_success
}

# ── Validate Manifest ────────────────────────────────────────

@test "validate_manifest accepts valid manifest" {
  snapshot_pre_install_state
  run validate_manifest
  assert_success
}

@test "validate_manifest rejects missing manifest" {
  run validate_manifest
  assert_failure
}

@test "validate_manifest rejects invalid JSON" {
  mkdir -p "$BACKUP_DIR"
  echo "not json" > "$MANIFEST_FILE"
  run validate_manifest
  assert_failure
}

@test "validate_manifest rejects wrong version" {
  mkdir -p "$BACKUP_DIR"
  echo '{"manifest_version":99,"pre_existing":{},"installed":{}}' > "$MANIFEST_FILE"
  run validate_manifest
  assert_failure
}

@test "validate_manifest rejects missing pre_existing" {
  mkdir -p "$BACKUP_DIR"
  echo '{"manifest_version":1,"installed":{}}' > "$MANIFEST_FILE"
  run validate_manifest
  assert_failure
}

# ── Uninstall ────────────────────────────────────────────────

@test "uninstall removes forge-installed files" {
  snapshot_pre_install_state

  # Simulate forge install
  echo "forge claude" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"persona":"senior"}' > "$CLAUDE_DIR/profile.json"
  echo "#!/bin/bash" > "$CLAUDE_DIR/statusline-command.sh"
  mkdir -p "$CLAUDE_DIR/rules"
  echo "rule" > "$CLAUDE_DIR/rules/agent-orchestration.md"

  update_manifest_installed "senior-engineer"
  uninstall_forge

  assert [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]
  assert [ ! -f "$CLAUDE_DIR/profile.json" ]
  assert [ ! -f "$CLAUDE_DIR/statusline-command.sh" ]
  assert [ ! -f "$CLAUDE_DIR/rules/agent-orchestration.md" ]
}

@test "uninstall restores pre-existing CLAUDE.md" {
  echo "my original config" > "$CLAUDE_DIR/CLAUDE.md"
  snapshot_pre_install_state

  echo "forge replaced this" > "$CLAUDE_DIR/CLAUDE.md"
  update_manifest_installed "senior-engineer"
  uninstall_forge

  run cat "$CLAUDE_DIR/CLAUDE.md"
  assert_output "my original config"
}

@test "uninstall restores pre-existing settings.json" {
  echo '{"myKey":"myValue"}' > "$CLAUDE_DIR/settings.json"
  snapshot_pre_install_state

  # Simulate forge merge
  echo '{"myKey":"myValue","statusLine":{"type":"command"},"alwaysThinkingEnabled":true}' > "$CLAUDE_DIR/settings.json"
  update_manifest_installed "senior-engineer"
  uninstall_forge

  run jq -r '.myKey' "$CLAUDE_DIR/settings.json"
  assert_output "myValue"
  # Forge additions should be gone
  run jq -r '.statusLine // "null"' "$CLAUDE_DIR/settings.json"
  assert_output "null"
}

@test "uninstall preserves user's own rules files" {
  mkdir -p "$CLAUDE_DIR/rules"
  echo "user rule" > "$CLAUDE_DIR/rules/my-custom-rule.md"
  snapshot_pre_install_state

  # Simulate forge adding its own rule
  echo "forge rule" > "$CLAUDE_DIR/rules/agent-orchestration.md"
  update_manifest_installed "senior-engineer"
  uninstall_forge

  # User's rule should still exist (restored from backup)
  assert [ -f "$CLAUDE_DIR/rules/my-custom-rule.md" ]
  run cat "$CLAUDE_DIR/rules/my-custom-rule.md"
  assert_output "user rule"

  # Forge rule should be gone
  assert [ ! -f "$CLAUDE_DIR/rules/agent-orchestration.md" ]
}

@test "uninstall preserves user files added post-install" {
  snapshot_pre_install_state

  # Simulate forge install
  mkdir -p "$CLAUDE_DIR/rules"
  echo "forge rule" > "$CLAUDE_DIR/rules/agent-orchestration.md"
  update_manifest_installed "senior-engineer"

  # User adds their own rule AFTER install
  echo "post-install rule" > "$CLAUDE_DIR/rules/my-new-rule.md"

  uninstall_forge

  # User's post-install rule should survive (not in manifest)
  assert [ -f "$CLAUDE_DIR/rules/my-new-rule.md" ]
  run cat "$CLAUDE_DIR/rules/my-new-rule.md"
  assert_output "post-install rule"
}

@test "uninstall removes empty directories" {
  snapshot_pre_install_state

  # Simulate forge install with only forge files in scripts/
  mkdir -p "$CLAUDE_DIR/scripts"
  echo "#!/bin/bash" > "$CLAUDE_DIR/scripts/generate-project-claude.sh"
  update_manifest_installed "senior-engineer"
  uninstall_forge

  # scripts/ should be removed since it's empty after removing forge files
  assert [ ! -d "$CLAUDE_DIR/scripts" ]
}

@test "uninstall cleans up forge-backup/ directory" {
  echo "original" > "$CLAUDE_DIR/CLAUDE.md"
  snapshot_pre_install_state
  echo "forge" > "$CLAUDE_DIR/CLAUDE.md"
  update_manifest_installed "senior-engineer"
  uninstall_forge

  assert [ ! -d "$BACKUP_DIR" ]
}

@test "show_uninstall_preview outputs removal and restore lists" {
  echo "original" > "$CLAUDE_DIR/CLAUDE.md"
  snapshot_pre_install_state

  echo "forge" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"persona":"se"}' > "$CLAUDE_DIR/profile.json"
  update_manifest_installed "senior-engineer"

  run show_uninstall_preview
  assert_success
  assert_output --partial "CLAUDE.md"
  assert_output --partial "restore"
}

@test "uninstall with no manifest does best-effort cleanup" {
  # Create forge files without a manifest
  echo "forge" > "$CLAUDE_DIR/CLAUDE.md"
  echo '{"p":"s"}' > "$CLAUDE_DIR/profile.json"
  echo "#!/bin/bash" > "$CLAUDE_DIR/statusline-command.sh"
  mkdir -p "$CLAUDE_DIR/rules"
  echo "rule" > "$CLAUDE_DIR/rules/agent-orchestration.md"
  mkdir -p "$CLAUDE_DIR/hooks"
  echo "hook" > "$CLAUDE_DIR/hooks/session-init.sh"
  mkdir -p "$CLAUDE_DIR/scripts"
  echo "script" > "$CLAUDE_DIR/scripts/generate-project-claude.sh"

  run uninstall_forge
  assert_success

  assert [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]
  assert [ ! -f "$CLAUDE_DIR/profile.json" ]
  assert [ ! -f "$CLAUDE_DIR/statusline-command.sh" ]
  assert [ ! -f "$CLAUDE_DIR/rules/agent-orchestration.md" ]
  assert [ ! -f "$CLAUDE_DIR/hooks/session-init.sh" ]
  assert [ ! -f "$CLAUDE_DIR/scripts/generate-project-claude.sh" ]
}
