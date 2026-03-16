#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-doctor — diagnostic health checks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Grouped checks: file integrity, hooks, CLAUDE.md freshness,
# settings, plugins, manifest, version.
#
# Usage:
#   forge doctor

cmd_doctor() {
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/settings-merge.sh"
  source "$FORGE_SOURCE_DIR/lib/plugins.sh"
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  banner "Doctor"

  local pass=0
  local warnings=0
  local failures=0

  # ── Manifest ───────────────────────────────────────────────
  step "Manifest"

  if [ -f "$MANIFEST_FILE" ]; then
    if validate_manifest 2>/dev/null; then
      ok "Manifest valid"; ((pass++))
    else
      fail "Manifest validation failed"; ((failures++))
    fi

    # Version check
    local installed_version source_version
    installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    source_version="$FORGE_VERSION"
    if [ "$installed_version" = "$source_version" ]; then
      ok "Version $source_version"; ((pass++))
    else
      warn "Version mismatch: installed=$installed_version source=$source_version"; ((warnings++))
    fi

    # Manifest v2 migration check
    local manifest_ver
    manifest_ver=$(jq -r '.manifest_version // 0' "$MANIFEST_FILE" 2>/dev/null)
    if [ "$manifest_ver" -ge 2 ] 2>/dev/null; then
      ok "Manifest schema v$manifest_ver"; ((pass++))
    else
      warn "Manifest needs migration (v$manifest_ver → v$MANIFEST_VERSION)"; ((warnings++))
    fi
  else
    fail "No manifest found at $MANIFEST_FILE"; ((failures++))
  fi

  # ── File Integrity ─────────────────────────────────────────
  step "File Integrity"

  local file_pass=0
  local file_issues=0

  # Rules
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    local src="$FORGE_SOURCE_DIR/templates/rules/${rule}.md"
    local dst="$CLAUDE_DIR/rules/${rule}.md"
    if [ ! -f "$dst" ]; then
      fail "Missing: rules/${rule}.md"; ((failures++)); ((file_issues++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      warn "Modified: rules/${rule}.md"; ((warnings++)); ((file_issues++))
    else
      ((pass++)); ((file_pass++))
    fi
  done < <(forge_shipped_rules)

  # Hooks
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    local src="$FORGE_SOURCE_DIR/hooks/${hook}.sh"
    local dst="$CLAUDE_DIR/hooks/${hook}.sh"
    if [ ! -f "$dst" ]; then
      fail "Missing: hooks/${hook}.sh"; ((failures++)); ((file_issues++))
    elif [ ! -x "$dst" ]; then
      fail "Not executable: hooks/${hook}.sh"; ((failures++)); ((file_issues++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      warn "Modified: hooks/${hook}.sh"; ((warnings++)); ((file_issues++))
    else
      ((pass++)); ((file_pass++))
    fi
  done < <(forge_shipped_hooks)

  # Scripts
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    local src="$FORGE_SOURCE_DIR/scripts/${script}.sh"
    local dst="$CLAUDE_DIR/scripts/${script}.sh"
    if [ ! -f "$dst" ]; then
      fail "Missing: scripts/${script}.sh"; ((failures++)); ((file_issues++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      warn "Modified: scripts/${script}.sh"; ((warnings++)); ((file_issues++))
    else
      ((pass++)); ((file_pass++))
    fi
  done < <(forge_shipped_scripts)

  # Root files
  for file in statusline-command.sh; do
    local src="$FORGE_SOURCE_DIR/$file"
    local dst="$CLAUDE_DIR/$file"
    if [ ! -f "$dst" ]; then
      fail "Missing: $file"; ((failures++)); ((file_issues++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      warn "Modified: $file"; ((warnings++)); ((file_issues++))
    else
      ((pass++)); ((file_pass++))
    fi
  done

  # Lib files
  for file in "${FORGE_LIB_FILES[@]}"; do
    local src="$FORGE_SOURCE_DIR/lib/$file"
    local dst="$CLAUDE_DIR/lib/$file"
    if [ ! -f "$dst" ]; then
      fail "Missing: lib/$file"; ((failures++)); ((file_issues++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      warn "Modified: lib/$file"; ((warnings++)); ((file_issues++))
    else
      ((pass++)); ((file_pass++))
    fi
  done

  if [ "$file_issues" -eq 0 ]; then
    ok "$file_pass files verified"
  fi

  # ── Hook Configuration ─────────────────────────────────────
  step "Hook Configuration"

  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local hooks_ok=true
    while IFS= read -r hook_name; do
      [ -n "$hook_name" ] || continue
      if jq -e --arg cmd "$hook_name" '
        [.hooks[][] | .hooks[]?.command // empty] | any(contains($cmd))
      ' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
        ((pass++))
      else
        warn "Hook not configured: $hook_name"; ((warnings++))
        hooks_ok=false
      fi
    done < <(forge_shipped_hooks)
    if [ "$hooks_ok" = true ]; then
      ok "All hooks configured"
    fi
  else
    fail "settings.json missing — cannot check hooks"; ((failures++))
  fi

  # ── CLAUDE.md Freshness ────────────────────────────────────
  step "CLAUDE.md"

  if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    local temp_md
    temp_md="$(get_temp_dir)/claude-forge-doctor-check.md"
    if assemble_claude_md "$CLAUDE_DIR/profile.json" "$temp_md" 2>/dev/null; then
      if diff -q <(tail -n +2 "$temp_md") <(tail -n +2 "$CLAUDE_DIR/CLAUDE.md") >/dev/null 2>&1; then
        local md_lines
        md_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
        ok "Matches profile ($md_lines lines)"; ((pass++))
      else
        warn "CLAUDE.md differs from current profile — run 'forge switch $(jq -r .persona "$CLAUDE_DIR/profile.json")' to refresh"
        ((warnings++))
      fi
      rm -f "$temp_md"
    else
      fail "Could not assemble CLAUDE.md for comparison"; ((failures++))
    fi
  else
    fail "profile.json or CLAUDE.md missing"; ((failures++))
  fi

  # ── Plugin Status ──────────────────────────────────────────
  step "Plugins"

  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local installed_group="full"
    if [ -f "$MANIFEST_FILE" ]; then
      installed_group=$(jq -r '.plugin_group // "full"' "$MANIFEST_FILE" 2>/dev/null)
    fi

    local expected_plugins expected_count actual_count
    expected_plugins=$(resolve_plugin_list "$installed_group" 2>/dev/null)
    expected_count=$(echo "$expected_plugins" | grep -c . || echo 0)
    actual_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)

    if [ "$actual_count" -ge "$expected_count" ]; then
      ok "$actual_count plugins enabled (group: $installed_group)"; ((pass++))
    elif [ "$actual_count" -gt 0 ]; then
      warn "$actual_count/$expected_count plugins enabled (group: $installed_group)"; ((warnings++))
    else
      fail "No plugins enabled"; ((failures++))
    fi
  fi

  # ── CLI ────────────────────────────────────────────────────
  step "CLI"

  if [ -L "$CLAUDE_DIR/bin/forge" ]; then
    local link_target
    link_target=$(readlink "$CLAUDE_DIR/bin/forge" 2>/dev/null || echo "")
    if [ -x "$link_target" ]; then
      ok "forge symlink OK"; ((pass++))
    else
      warn "forge symlink target not executable: $link_target"; ((warnings++))
    fi
  elif [ -f "$CLAUDE_DIR/bin/forge" ]; then
    if is_windows 2>/dev/null; then
      ok "forge installed (copy)"; ((pass++))
    else
      warn "forge exists but is not a symlink (may become stale)"; ((warnings++))
    fi
  else
    info "forge not installed at ~/.claude/bin/forge"
  fi

  # ── Summary ────────────────────────────────────────────────
  echo ""
  local total=$((pass + warnings + failures))
  if [ "$failures" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    printf "${_C_GREEN}${_C_BOLD}Your system is ready.${_C_RST} %d checks passed.\n" "$total"
  elif [ "$failures" -eq 0 ]; then
    printf "${_C_GREEN}✓${_C_RST} %d/%d checks passed, ${_C_YELLOW}%d warning(s)${_C_RST}\n" "$pass" "$total" "$warnings"
  else
    printf "${_C_RED}✗${_C_RST} ${_C_RED}%d failure(s)${_C_RST}, ${_C_YELLOW}%d warning(s)${_C_RST} out of %d checks\n" "$failures" "$warnings" "$total"
    return 1
  fi
}
