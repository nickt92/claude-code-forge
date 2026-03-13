#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Settings Merge — integration tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/settings-merge.sh"
  TEMPLATE="$SCRIPT_DIR/templates/settings.json"
}

teardown() {
  teardown_sandbox
}

# ── Fresh Install ────────────────────────────────────────────

@test "merging template with empty object produces valid JSON" {
  echo '{}' > "$TEST_SANDBOX/empty.json"
  merge_settings "$TEST_SANDBOX/empty.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"
  run jq -e '.' "$TEST_SANDBOX/merged.json"
  assert_success
}

@test "merging template with empty object preserves all hooks" {
  echo '{}' > "$TEST_SANDBOX/empty.json"
  merge_settings "$TEST_SANDBOX/empty.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  run jq -r '.hooks | keys[]' "$TEST_SANDBOX/merged.json"
  assert_success
  assert_output --partial "UserPromptSubmit"
  assert_output --partial "PreToolUse"
  assert_output --partial "PreCompact"
}

# ── Additive Merge Preserves User Hooks ──────────────────────

@test "preserves existing user hooks during merge" {
  cat > "$TEST_SANDBOX/existing.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/my-custom-hook.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF
  merge_settings "$TEST_SANDBOX/existing.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  # User's custom hook should still be present
  run jq -r '.hooks.UserPromptSubmit[].hooks[].command' "$TEST_SANDBOX/merged.json"
  assert_output --partial "my-custom-hook.sh"
  # Template's session-init should also be present
  assert_output --partial "session-init.sh"
}

# ── Hook Dedup by Command ───────────────────────────────────

@test "deduplicates hooks by command string" {
  # Existing settings already has session-init
  cat > "$TEST_SANDBOX/existing.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-init.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
EOF
  merge_settings "$TEST_SANDBOX/existing.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  # Should have exactly 1 session-init entry, not 2
  local count
  count=$(jq '[.hooks.UserPromptSubmit[].hooks[].command | select(contains("session-init"))] | length' "$TEST_SANDBOX/merged.json")
  assert [ "$count" -eq 1 ]
}

# ── Plugin Merge ─────────────────────────────────────────────

@test "preserves user plugins during merge" {
  cat > "$TEST_SANDBOX/existing.json" <<'EOF'
{
  "enabledPlugins": {
    "my-custom-plugin@my-repo": true
  }
}
EOF
  merge_settings "$TEST_SANDBOX/existing.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  run jq -r '.enabledPlugins["my-custom-plugin@my-repo"]' "$TEST_SANDBOX/merged.json"
  assert_output "true"
}

@test "adds forge plugins when user has none" {
  echo '{}' > "$TEST_SANDBOX/empty.json"
  merge_settings "$TEST_SANDBOX/empty.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  local count
  count=$(jq '.enabledPlugins | length' "$TEST_SANDBOX/merged.json")
  assert [ "$count" -ge 15 ]
}

# ── Preserves Unknown User Keys ──────────────────────────────

@test "preserves unknown user settings keys" {
  cat > "$TEST_SANDBOX/existing.json" <<'EOF'
{
  "myCustomSetting": "preserved",
  "hooks": {}
}
EOF
  merge_settings "$TEST_SANDBOX/existing.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  run jq -r '.myCustomSetting' "$TEST_SANDBOX/merged.json"
  assert_output "preserved"
}

# ── Output Validity ──────────────────────────────────────────

@test "merged output has all required top-level keys" {
  echo '{}' > "$TEST_SANDBOX/empty.json"
  merge_settings "$TEST_SANDBOX/empty.json" "$TEMPLATE" "$TEST_SANDBOX/merged.json"

  run jq -e '.hooks and .enabledPlugins and .statusLine and .alwaysThinkingEnabled' "$TEST_SANDBOX/merged.json"
  assert_success
}
