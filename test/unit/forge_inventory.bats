#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge-inventory.sh — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
}

teardown() {
  teardown_sandbox
}

# ── Commands ─────────────────────────────────────────────────

@test "shipped commands includes known commands" {
  local commands
  commands=$(forge_shipped_commands)
  echo "$commands" | grep -q "dashboard"
  echo "$commands" | grep -q "audit"
  echo "$commands" | grep -q "analyze"
}

@test "shipped commands are newline-separated" {
  local commands
  commands=$(forge_shipped_commands)
  local count
  count=$(echo "$commands" | wc -l | tr -d ' ')
  [ "$count" -gt 1 ]
}

@test "shipped commands have no .sh extension" {
  local commands
  commands=$(forge_shipped_commands)
  ! echo "$commands" | grep -q '\.sh'
}

@test "shipped commands have no cmd- prefix" {
  local commands
  commands=$(forge_shipped_commands)
  ! echo "$commands" | grep -q '^cmd-'
}

# ── Rules ────────────────────────────────────────────────────

@test "shipped rules lists rule files" {
  local rules
  rules=$(forge_shipped_rules)
  [ -n "$rules" ]
}

@test "shipped rules have no .md extension" {
  local rules
  rules=$(forge_shipped_rules)
  ! echo "$rules" | grep -q '\.md'
}

@test "shipped rules have no duplicates" {
  local rules
  rules=$(forge_shipped_rules)
  local unique_count
  unique_count=$(echo "$rules" | sort -u | wc -l | tr -d ' ')
  local total_count
  total_count=$(echo "$rules" | wc -l | tr -d ' ')
  [ "$unique_count" -eq "$total_count" ]
}

# ── Hooks ────────────────────────────────────────────────────

@test "shipped hooks lists hook files" {
  local hooks
  hooks=$(forge_shipped_hooks)
  echo "$hooks" | grep -q "command-guard"
  echo "$hooks" | grep -q "backup-transcript"
}

@test "shipped hooks have no .sh extension" {
  local hooks
  hooks=$(forge_shipped_hooks)
  ! echo "$hooks" | grep -q '\.sh'
}

# ── Scripts ──────────────────────────────────────────────────

@test "shipped scripts lists script files" {
  local scripts
  scripts=$(forge_shipped_scripts)
  [ -n "$scripts" ]
}

@test "shipped scripts have no .sh extension" {
  local scripts
  scripts=$(forge_shipped_scripts)
  ! echo "$scripts" | grep -q '\.sh'
}

@test "shipped scripts are newline-separated" {
  local scripts
  scripts=$(forge_shipped_scripts)
  local count
  count=$(echo "$scripts" | wc -l | tr -d ' ')
  [ "$count" -ge 1 ]
}
