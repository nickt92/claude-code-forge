#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install Flow — end-to-end integration tests (non-interactive)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests the --profile flag path (no interactive wizard).
# Skips plugin installation (requires `claude` CLI).

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/settings-merge.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
}

teardown() {
  teardown_sandbox
}

# Simulate the core install logic without requiring `claude` CLI
# or interactive prompts — focuses on file operations.
simulate_install() {
  local persona="$1"
  local profile_file="$PROFILES_DIR/${persona}.json"

  [ ! -f "$profile_file" ] && return 1

  mkdir -p "$CLAUDE_DIR"/{rules,hooks,scripts,backups,plans}

  # Backup existing
  [ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.backup"
  [ -f "$CLAUDE_DIR/settings.json" ] && cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.backup"
  [ -f "$CLAUDE_DIR/profile.json" ] && cp "$CLAUDE_DIR/profile.json" "$CLAUDE_DIR/profile.json.backup"

  # Assemble CLAUDE.md
  assemble_claude_md "$profile_file" "$CLAUDE_DIR/CLAUDE.md"

  # Copy profile
  cp "$profile_file" "$CLAUDE_DIR/profile.json"

  # Copy rules
  for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
    cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  done

  # Copy hooks
  for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
    cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  done

  # Copy scripts
  for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
    [ -f "$script_file" ] && cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    [ -f "$script_file" ] && chmod +x "$CLAUDE_DIR/scripts/$(basename "$script_file")"
  done

  # Copy status line
  cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"

  # Settings merge
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    merge_settings "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json.tmp"
    mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
  else
    cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
  fi
}

# ── Core Install ─────────────────────────────────────────────

@test "install creates CLAUDE.md" {
  simulate_install "senior-engineer"
  assert [ -f "$CLAUDE_DIR/CLAUDE.md" ]
}

@test "install creates profile.json with correct persona" {
  simulate_install "senior-engineer"
  run jq -r '.persona' "$CLAUDE_DIR/profile.json"
  assert_output "senior-engineer"
}

@test "install copies all rules files" {
  simulate_install "senior-engineer"
  local expected_rules=(agent-orchestration commit-and-delivery context-and-memory project-setup pull-requests quality-engineering)
  for rule in "${expected_rules[@]}"; do
    assert [ -f "$CLAUDE_DIR/rules/${rule}.md" ]
  done
}

@test "install copies all hooks and makes them executable" {
  simulate_install "senior-engineer"
  local expected_hooks=(session-init architect-gate commit-validator backup-transcript)
  for hook in "${expected_hooks[@]}"; do
    assert [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ]
    assert [ -x "$CLAUDE_DIR/hooks/${hook}.sh" ]
  done
}

@test "install creates settings.json with hooks" {
  simulate_install "senior-engineer"
  run jq -e '.hooks' "$CLAUDE_DIR/settings.json"
  assert_success
}

@test "install copies statusline-command.sh" {
  simulate_install "senior-engineer"
  assert [ -f "$CLAUDE_DIR/statusline-command.sh" ]
  assert [ -x "$CLAUDE_DIR/statusline-command.sh" ]
}

# ── Unknown Profile Fails ────────────────────────────────────

@test "install fails for unknown profile" {
  run simulate_install "nonexistent-profile"
  assert_failure
}

# ── Backup Logic ─────────────────────────────────────────────

@test "install backs up existing CLAUDE.md" {
  echo "original content" > "$CLAUDE_DIR/CLAUDE.md"
  simulate_install "senior-engineer"

  assert [ -f "$CLAUDE_DIR/CLAUDE.md.backup" ]
  run cat "$CLAUDE_DIR/CLAUDE.md.backup"
  assert_output "original content"
}

@test "install backs up existing settings.json" {
  echo '{"custom":"setting"}' > "$CLAUDE_DIR/settings.json"
  simulate_install "senior-engineer"

  assert [ -f "$CLAUDE_DIR/settings.json.backup" ]
  run jq -r '.custom' "$CLAUDE_DIR/settings.json.backup"
  assert_output "setting"
}

# ── Idempotency ──────────────────────────────────────────────

@test "installing twice produces same result" {
  simulate_install "senior-engineer"
  local first_md first_profile
  first_md=$(tail -n +2 "$CLAUDE_DIR/CLAUDE.md")  # skip date header
  first_profile=$(cat "$CLAUDE_DIR/profile.json")

  simulate_install "senior-engineer"
  local second_md second_profile
  second_md=$(tail -n +2 "$CLAUDE_DIR/CLAUDE.md")
  second_profile=$(cat "$CLAUDE_DIR/profile.json")

  assert [ "$first_md" = "$second_md" ]
  assert [ "$first_profile" = "$second_profile" ]
}

@test "installing twice does not duplicate hooks" {
  simulate_install "senior-engineer"
  simulate_install "senior-engineer"

  local session_init_count
  session_init_count=$(jq '[.hooks.UserPromptSubmit[].hooks[].command | select(contains("session-init"))] | length' "$CLAUDE_DIR/settings.json")
  assert [ "$session_init_count" -eq 1 ]
}

# ── Different Profile Switch ─────────────────────────────────

@test "switching profile changes CLAUDE.md content" {
  simulate_install "senior-engineer"
  local se_lines
  se_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')

  simulate_install "vibe-coder"
  local vc_lines
  vc_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')

  # Different personas produce different line counts
  assert [ "$se_lines" -ne "$vc_lines" ]

  # Profile should reflect the new persona
  run jq -r '.persona' "$CLAUDE_DIR/profile.json"
  assert_output "vibe-coder"
}
