#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge restore — settings history and rollback
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Before this existed there was exactly one restore point ever: the backup
# taken at first install. A user installed for a year had a single snapshot
# from a year ago, and no way to undo one bad operation.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  export FORGE_VERSION="1.4.0"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/manifest.sh"
  source "$SCRIPT_DIR/lib/cmd-restore.sh"
  mkdir -p "$BACKUP_DIR"
}

teardown() {
  teardown_sandbox
}

_settings() { echo "$1" > "$CLAUDE_DIR/settings.json"; }
_history_count() {
  find "$SETTINGS_HISTORY_DIR" -name 'settings-*.json' -type f 2>/dev/null | wc -l | tr -d ' '
}

# ── Snapshot capture ─────────────────────────────────────────

@test "snapshot writes a labelled copy of settings.json" {
  _settings '{"a":1}'
  snapshot_settings_history "install"

  run _history_count
  assert_output "1"
  run bash -c "ls '$SETTINGS_HISTORY_DIR' | head -1"
  assert_output --partial "install"
}

@test "snapshot is a no-op when there is no settings.json" {
  snapshot_settings_history "install"
  run _history_count
  assert_output "0"
}

@test "two snapshots in the same second do not overwrite each other" {
  _settings '{"a":1}'
  snapshot_settings_history "install"
  _settings '{"a":2}'
  snapshot_settings_history "install"

  run _history_count
  assert_output "2"
}

@test "a label cannot escape the history directory" {
  _settings '{"a":1}'
  snapshot_settings_history "../../escape"

  # Nothing written outside the history dir
  assert [ ! -e "$BACKUP_DIR/../escape.json" ]
  run _history_count
  assert_output "1"
}

@test "history is pruned to the keep limit, dropping the oldest" {
  export SETTINGS_HISTORY_KEEP=3
  mkdir -p "$SETTINGS_HISTORY_DIR"
  # Hand-seed older snapshots; names are UTC-stamped so lexical order is age.
  for stamp in 20200101T000001Z 20200101T000002Z 20200101T000003Z 20200101T000004Z; do
    echo '{"old":true}' > "$SETTINGS_HISTORY_DIR/settings-${stamp}-install.json"
  done
  _settings '{"new":true}'
  snapshot_settings_history "install"

  run _history_count
  assert_output "3"
  # The oldest must be the one that went
  assert [ ! -f "$SETTINGS_HISTORY_DIR/settings-20200101T000001Z-install.json" ]
}

# ── Listing ──────────────────────────────────────────────────

@test "restore --list reports when there is no history yet" {
  run cmd_restore --list
  assert_success
  assert_output --partial "No operation snapshots yet"
}

@test "restore --list shows snapshots with a decoded timestamp" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  echo '{"a":1}' > "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-permissions.json"

  run cmd_restore --list
  assert_success
  assert_output --partial "2026-07-26 10:15:00 UTC"
  assert_output --partial "permissions"
}

@test "restore --list marks the snapshot matching current settings" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  _settings '{"a":1}'
  cp "$CLAUDE_DIR/settings.json" "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-install.json"

  run cmd_restore --list
  assert_success
  assert_output --partial "identical to your current"
}

# ── Restoring ────────────────────────────────────────────────

@test "restore --latest puts the newest snapshot back" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  echo '{"generation":1}' > "$SETTINGS_HISTORY_DIR/settings-20260101T000000Z-install.json"
  echo '{"generation":2}' > "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-permissions.json"
  _settings '{"generation":3}'

  run cmd_restore --latest --yes
  assert_success

  run jq -r '.generation' "$CLAUDE_DIR/settings.json"
  assert_output "2"
}

@test "restoring snapshots the current state first, so it can be undone" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  echo '{"generation":1}' > "$SETTINGS_HISTORY_DIR/settings-20260101T000000Z-install.json"
  _settings '{"generation":99}'

  run cmd_restore --latest --yes
  assert_success

  # The state we replaced is now itself recoverable
  run bash -c "grep -l '\"generation\":99' '$SETTINGS_HISTORY_DIR'/*pre-restore*.json | wc -l | tr -d ' '"
  assert_output "1"
}

@test "restore accepts a bare timestamp" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  echo '{"generation":7}' > "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-install.json"
  _settings '{"generation":0}'

  run cmd_restore 20260726T101500Z --yes
  assert_success
  run jq -r '.generation' "$CLAUDE_DIR/settings.json"
  assert_output "7"
}

@test "restore refuses an ambiguous match rather than guessing" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  echo '{"a":1}' > "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-install.json"
  echo '{"a":2}' > "$SETTINGS_HISTORY_DIR/settings-20260726T101501Z-install.json"
  _settings '{"a":0}'

  run cmd_restore install --yes
  assert_failure
  assert_output --partial "Ambiguous"
  # Current settings untouched
  run jq -r '.a' "$CLAUDE_DIR/settings.json"
  assert_output "0"
}

@test "restore rejects an unknown snapshot" {
  _settings '{"a":0}'
  run cmd_restore nope-does-not-exist --yes
  assert_failure
  assert_output --partial "No snapshot matching"
}

@test "restore refuses to install invalid JSON over working settings" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  printf 'not json {' > "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-install.json"
  _settings '{"good":true}'

  run cmd_restore --latest --yes
  assert_failure
  assert_output --partial "not valid JSON"
  # The good settings survive
  run jq -r '.good' "$CLAUDE_DIR/settings.json"
  assert_output "true"
}

@test "restore --pre-install returns the original pre-forge settings" {
  echo '{"before":"forge"}' > "$BACKUP_DIR/settings.json"
  _settings '{"after":"forge"}'

  run cmd_restore --pre-install --yes
  assert_success
  run jq -r '.before' "$CLAUDE_DIR/settings.json"
  assert_output "forge"
}

@test "restore is a no-op when already identical" {
  mkdir -p "$SETTINGS_HISTORY_DIR"
  _settings '{"same":true}'
  cp "$CLAUDE_DIR/settings.json" "$SETTINGS_HISTORY_DIR/settings-20260726T101500Z-install.json"

  run cmd_restore --latest --yes
  assert_success
  assert_output --partial "nothing to do"
}

@test "restore fails cleanly when forge is not installed" {
  rm -rf "$BACKUP_DIR"
  run cmd_restore --list
  assert_failure
  assert_output --partial "not installed"
}

@test "restore --help documents the subcommands" {
  run cmd_restore --help
  assert_success
  assert_output --partial "forge restore"
  assert_output --partial "--list"
  assert_output --partial "--pre-install"
}

# ── Through the real dispatcher ───────────────────────────────
# The tests above source manifest.sh in setup, which masked a real bug: the
# forge dispatcher sources only ui.sh and lib/cmd-<name>.sh, so
# SETTINGS_HISTORY_DIR was unset at runtime and every snapshot was invisible.
# These invoke the CLI the way a user does.

@test "forge restore --list works through the dispatcher" {
  mkdir -p "$CLAUDE_DIR/forge-backup/history"
  echo '{"a":1}' > "$CLAUDE_DIR/forge-backup/history/settings-20260726T101500Z-install.json"
  echo '{"a":2}' > "$CLAUDE_DIR/settings.json"

  run env HOME="$TEST_SANDBOX" "$SCRIPT_DIR/forge" restore --list
  assert_success
  assert_output --partial "settings-20260726T101500Z-install.json"
  assert_output --partial "2026-07-26 10:15:00 UTC"
}

@test "forge restore --latest works through the dispatcher" {
  mkdir -p "$CLAUDE_DIR/forge-backup/history"
  echo '{"generation":1}' > "$CLAUDE_DIR/forge-backup/history/settings-20260726T101500Z-install.json"
  echo '{"generation":9}' > "$CLAUDE_DIR/settings.json"

  run env HOME="$TEST_SANDBOX" "$SCRIPT_DIR/forge" restore --latest --yes
  assert_success

  run jq -r '.generation' "$CLAUDE_DIR/settings.json"
  assert_output "1"
}
