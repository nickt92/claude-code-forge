#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-checks.sh — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/install-checks.sh"
}

teardown() {
  teardown_sandbox
}

# Helper: set up a healthy install in the sandbox
setup_healthy_install() {
  # CLAUDE.md and profile.json
  echo "# Test" > "$CLAUDE_DIR/CLAUDE.md"
  create_test_profile

  # Rules
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    echo "# $rule" > "$CLAUDE_DIR/rules/${rule}.md"
  done < <(forge_shipped_rules)

  # Hooks
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    echo '#!/bin/bash' > "$CLAUDE_DIR/hooks/${hook}.sh"
    chmod +x "$CLAUDE_DIR/hooks/${hook}.sh"
  done < <(forge_shipped_hooks)

  # Status line
  echo '#!/bin/bash' > "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"

  # Settings
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "hooks": {"PreToolUse": []},
  "statusLine": "forge-sl",
  "enabledPlugins": {"a":true,"b":true,"c":true,"d":true,"e":true}
}
EOF
}

# ── Healthy Install ──────────────────────────────────────────

@test "healthy install returns 0" {
  setup_healthy_install
  run _install_run_health_checks
  assert_success
}

@test "healthy install output says all passed" {
  setup_healthy_install
  run _install_run_health_checks
  assert_output --partial "passed"
}

# ── Missing Files ────────────────────────────────────────────

@test "missing CLAUDE.md causes failure" {
  setup_healthy_install
  rm -f "$CLAUDE_DIR/CLAUDE.md"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "CLAUDE.md missing"
}

@test "missing profile.json causes failure" {
  setup_healthy_install
  rm -f "$CLAUDE_DIR/profile.json"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "profile.json missing"
}

@test "missing settings.json causes failure" {
  setup_healthy_install
  rm -f "$CLAUDE_DIR/settings.json"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "settings.json missing"
}

@test "missing statusline causes failure" {
  setup_healthy_install
  rm -f "$CLAUDE_DIR/statusline-command.sh"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "statusline-command.sh missing"
}

# ── Non-executable Hooks ────────────────────────────────────

@test "non-executable hook is detected" {
  setup_healthy_install
  local first_hook
  first_hook=$(forge_shipped_hooks | head -1)
  chmod -x "$CLAUDE_DIR/hooks/${first_hook}.sh"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "not executable"
}

# ── Settings Structure ───────────────────────────────────────

@test "settings without hooks key fails" {
  setup_healthy_install
  echo '{"statusLine":"x","enabledPlugins":{"a":true,"b":true,"c":true,"d":true,"e":true}}' > "$CLAUDE_DIR/settings.json"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "hooks"
}

@test "settings without statusLine key fails" {
  setup_healthy_install
  echo '{"hooks":{},"enabledPlugins":{"a":true,"b":true,"c":true,"d":true,"e":true}}' > "$CLAUDE_DIR/settings.json"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "status line"
}

@test "settings with too few plugins warns" {
  setup_healthy_install
  echo '{"hooks":{"PreToolUse":[]},"statusLine":"x","enabledPlugins":{"a":true}}' > "$CLAUDE_DIR/settings.json"
  run _install_run_health_checks
  assert_success
  assert_output --partial "Only 1 plugin"
}

@test "settings with zero plugins fails" {
  setup_healthy_install
  echo '{"hooks":{"PreToolUse":[]},"statusLine":"x","enabledPlugins":{}}' > "$CLAUDE_DIR/settings.json"
  run _install_run_health_checks
  assert_failure
  assert_output --partial "No plugins"
}

# ── Assembly Smoke Test ──────────────────────────────────────

@test "assembly smoke test passes for shipped profiles" {
  setup_healthy_install
  run _install_run_health_checks
  assert_success
  assert_output --partial "assemblies"
}

# ── Return Codes ─────────────────────────────────────────────

@test "multiple failures still returns non-zero" {
  setup_healthy_install
  rm -f "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/profile.json"
  run _install_run_health_checks
  assert_failure
}
