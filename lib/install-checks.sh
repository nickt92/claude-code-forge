#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-checks — post-install health verification
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Sourced by cmd-install.sh. Requires ui.sh, forge-inventory.sh,
# assembly.sh, and platform.sh.

# ── Health Check Function ─────────────────────────────────────
_install_run_health_checks() {
  step "Verifying installation"

  local errors=0
  local health_pass=0
  local health_fail=0
  debug "starting health checks"

  # CLAUDE.md
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    ((health_pass++))
  else
    forge_fail "CLAUDE.md missing"; ((health_fail++)); ((errors++))
  fi

  # profile.json
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    ((health_pass++))
  else
    forge_fail "profile.json missing"; ((health_fail++)); ((errors++))
  fi

  # Rules files (discovered from source)
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    if [ -f "$CLAUDE_DIR/rules/${rule}.md" ]; then
      ((health_pass++))
    else
      forge_fail "rules/${rule}.md missing"; ((health_fail++)); ((errors++))
    fi
  done < <(forge_shipped_rules)

  # Hooks (discovered from source)
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ] && [ -x "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
      ((health_pass++))
    else
      forge_fail "hooks/${hook}.sh missing or not executable"; ((health_fail++)); ((errors++))
    fi
  done < <(forge_shipped_hooks)

  # Status line
  if [ -f "$CLAUDE_DIR/statusline-command.sh" ] && [ -x "$CLAUDE_DIR/statusline-command.sh" ]; then
    ((health_pass++))
  else
    forge_fail "statusline-command.sh missing or not executable"; ((health_fail++)); ((errors++))
  fi

  # Settings checks
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if jq -e '.hooks' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
      ((health_pass++))
    else
      forge_fail "settings.json missing hooks configuration"; ((health_fail++)); ((errors++))
    fi
    if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
      ((health_pass++))
    else
      forge_fail "settings.json missing status line configuration"; ((health_fail++)); ((errors++))
    fi
    local plugin_count
    plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
    # Permissive floor pending 1.4.0: the template enables the 'full' set
    # regardless of the chosen group, so this only sanity-checks that plugins
    # were enabled at all — not that they match the installed group.
    if [ "$plugin_count" -ge 5 ]; then
      ((health_pass++))
    elif [ "$plugin_count" -gt 0 ]; then
      warn "Only $plugin_count plugins enabled"; ((health_fail++))
    else
      forge_fail "No plugins enabled in settings.json"; ((health_fail++)); ((errors++))
    fi
  else
    forge_fail "settings.json missing"; ((health_fail++)); ((errors++))
  fi

  debug "health checks complete (pass=$health_pass fail=$health_fail)"

  # Assembly smoke test
  debug "starting assembly smoke tests"
  local assembly_pass=0
  local assembly_fail=0
  local persona_key temp_output line_count
  for profile_json in "$PROFILES_DIR"/*.json; do
    persona_key=$(jq -r '.persona' "$profile_json")
    temp_output="$(get_temp_dir)/claude-forge-test-${persona_key}.md"
    if assemble_claude_md "$profile_json" "$temp_output" 2>/dev/null; then
      line_count=$(wc -l < "$temp_output" | tr -d ' ')
      if [ "$line_count" -le 200 ]; then
        ((assembly_pass++))
      else
        warn "${persona_key}: ${line_count} lines (over 200 limit)"
        ((assembly_fail++))
      fi
      rm -f "$temp_output"
    else
      forge_fail "${persona_key}: assembly failed"
      ((assembly_fail++)); ((errors++))
    fi
  done

  local total_pass=$(( health_pass + assembly_pass ))

  if [ "$errors" -eq 0 ] && [ "$health_fail" -eq 0 ] && [ "$assembly_fail" -eq 0 ]; then
    ok "All checks passed (${health_pass} health, ${assembly_pass} assemblies)"
  else
    if [ "$health_fail" -gt 0 ] || [ "$assembly_fail" -gt 0 ]; then
      local total_checks=$(( health_pass + health_fail + assembly_pass + assembly_fail ))
      ok "${total_pass}/${total_checks} checks passed"
    fi
  fi

  return "$errors"
}
