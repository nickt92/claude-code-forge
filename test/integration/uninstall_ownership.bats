#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Uninstall ownership — forge must only remove what forge added
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge writes into a file the user also edits by hand. Ownership was
# INFERRED by diffing current settings against a backup frozen at first
# install, so any hook the user added afterwards looked identical to a forge
# addition — and uninstall deleted it. These tests pin the boundary.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  export FORGE_VERSION="1.4.0"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/manifest.sh"
  source "$SCRIPT_DIR/lib/settings-merge.sh"
  source "$SCRIPT_DIR/lib/settings-unmerge.sh"
}

teardown() {
  teardown_sandbox
}

# Settings containing one hook the user wrote themselves.
_seed_user_settings() {
  cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/scripts/user-original.sh"}]}
    ]
  },
  "enabledPlugins": {"user-plugin@somewhere": true}
}
JSON
}

# One forge-shipped hook, as the template would install it.
_merge_forge_template() {
  cat > "$TEST_SANDBOX/template.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/command-guard.sh"}]}
    ]
  },
  "enabledPlugins": {"forge-plugin@marketplace": true},
  "statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}
}
JSON
  merge_settings "$CLAUDE_DIR/settings.json" "$TEST_SANDBOX/template.json" "$CLAUDE_DIR/settings.json.new"
  mv "$CLAUDE_DIR/settings.json.new" "$CLAUDE_DIR/settings.json"
}

_hook_commands() {
  jq -r '.hooks.PreToolUse[]?.hooks[0].command' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort
}

_uninstall_settings() {
  local forge_additions
  forge_additions=$(jq -r '.installed.settings_additions // {}' "$MANIFEST_FILE" 2>/dev/null)
  unmerge_settings "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json" "$forge_additions"
}

# ── The data-loss case ───────────────────────────────────────

@test "a hook the user adds after install survives uninstall" {
  _seed_user_settings
  snapshot_pre_install_state          # backup frozen here, with only the user hook
  _merge_forge_template
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  # User adds their own hook later, then forge is reinstalled (forge update
  # does exactly this, and it re-runs update_manifest_installed).
  jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/scripts/user-later.sh"}]}]' \
    "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/s.tmp" && mv "$CLAUDE_DIR/s.tmp" "$CLAUDE_DIR/settings.json"
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  # forge must not have claimed the user's hook as its own
  run jq -r '[.installed.settings_additions.hooks.PreToolUse[]?.hooks[0].command] | join(",")' "$MANIFEST_FILE"
  refute_output --partial "user-later.sh"

  _uninstall_settings

  run _hook_commands
  assert_output --partial "user-original.sh"
  assert_output --partial "user-later.sh"
  refute_output --partial "command-guard.sh"
}

@test "a plugin the user enables after install survives uninstall" {
  _seed_user_settings
  snapshot_pre_install_state
  _merge_forge_template
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  jq '.enabledPlugins["user-later@somewhere"] = true' "$CLAUDE_DIR/settings.json" \
    > "$CLAUDE_DIR/s.tmp" && mv "$CLAUDE_DIR/s.tmp" "$CLAUDE_DIR/settings.json"
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  _uninstall_settings

  run jq -r '.enabledPlugins | keys | join(",")' "$CLAUDE_DIR/settings.json"
  assert_output --partial "user-plugin@somewhere"
  assert_output --partial "user-later@somewhere"
  refute_output --partial "forge-plugin@marketplace"
}

# ── The behaviour that must not regress ──────────────────────

@test "forge still removes its own hooks on uninstall" {
  _seed_user_settings
  snapshot_pre_install_state
  _merge_forge_template
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  _uninstall_settings

  run _hook_commands
  refute_output --partial "command-guard.sh"
  assert_output --partial "user-original.sh"
}

@test "forge does not claim a pre-existing hook it did not add" {
  # The user already had a hook pointing at a forge-shaped path before install.
  cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/command-guard.sh"}]}
    ]
  }
}
JSON
  snapshot_pre_install_state
  _merge_forge_template
  update_manifest_installed "senior-engineer" "$SCRIPT_DIR" "full" "$TEST_SANDBOX/template.json"

  _uninstall_settings

  # It was theirs first, and the backup restores it.
  run _hook_commands
  assert_output --partial "command-guard.sh"
}
