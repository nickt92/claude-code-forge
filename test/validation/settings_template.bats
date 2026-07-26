#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Settings Template — validation tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  SETTINGS="$PROJECT_ROOT/templates/settings.json"
}

# ── Valid JSON ───────────────────────────────────────────────

@test "settings.json is valid JSON" {
  run jq -e '.' "$SETTINGS"
  assert_success
}

# ── Hook Commands Reference Existing Scripts ─────────────────

@test "hook commands reference existing hook scripts" {
  # Extract all hook commands
  local commands
  commands=$(jq -r '.. | .command? // empty' "$SETTINGS" | grep "hooks/")

  while IFS= read -r cmd; do
    # Extract the script path (after "bash ")
    local script_name
    script_name=$(echo "$cmd" | grep -oE 'hooks/[a-z-]+\.sh')
    [ -z "$script_name" ] && continue
    assert [ -f "$PROJECT_ROOT/$script_name" ]
  done <<< "$commands"
}

# ── Plugin Count ─────────────────────────────────────────────

@test "settings template has 18 plugins" {
  run jq '.enabledPlugins | length' "$SETTINGS"
  assert_output "18"
}

# enabledPlugins and the 'full' plugin group are two separate sources of truth
# in the same name@marketplace dialect — guard them against silent drift so a
# plugin added to one without the other turns the build red. (Until 1.4.0
# derives enabledPlugins from the chosen group, the template's enabled set is
# the 'full' group.)
@test "enabledPlugins matches the full plugin group exactly" {
  local enabled full
  enabled=$(jq -r '.enabledPlugins | keys[]' "$SETTINGS" | sort)
  full=$(jq -r '.full[]' "$PROJECT_ROOT/templates/plugin-groups.json" | sort)
  assert_equal "$enabled" "$full"
}

# ── Reasonable Timeouts ─────────────────────────────────────

@test "hook timeouts are between 1 and 30 seconds" {
  local timeouts
  timeouts=$(jq -r '.. | .timeout? // empty' "$SETTINGS")

  while IFS= read -r timeout; do
    [ -z "$timeout" ] && continue
    assert [ "$timeout" -ge 1 ]
    assert [ "$timeout" -le 30 ]
  done <<< "$timeouts"
}
