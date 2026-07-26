#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-doctor — diagnostic health checks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Grouped checks: file integrity, hooks, CLAUDE.md freshness,
# settings, plugins, manifest, version.
#
# Usage:
#   forge doctor
#   forge doctor --json

cmd_doctor() {
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/settings-merge.sh"
  source "$FORGE_SOURCE_DIR/lib/plugins.sh"
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  local json_output=false
  if [ "${1:-}" = "--json" ]; then
    json_output=true
    shift
  fi

  local json_checks='[]'

  _doctor_add_check() {
    local category="$1" name="$2" status="$3" detail="${4:-}"
    if [ "$json_output" = true ]; then
      local entry
      if [ -n "$detail" ]; then
        entry=$(jq -n --arg c "$category" --arg n "$name" --arg s "$status" --arg d "$detail" \
          '{category: $c, name: $n, status: $s, detail: $d}')
      else
        entry=$(jq -n --arg c "$category" --arg n "$name" --arg s "$status" \
          '{category: $c, name: $n, status: $s}')
      fi
      json_checks=$(echo "$json_checks" | jq --argjson e "$entry" '. + [$e]')
    fi
  }

  [ "$json_output" != true ] && banner "Doctor"

  local pass=0
  local warnings=0
  local failures=0

  # ── Manifest ───────────────────────────────────────────────
  [ "$json_output" != true ] && step "Manifest"

  if [ -f "$MANIFEST_FILE" ]; then
    if validate_manifest 2>/dev/null; then
      [ "$json_output" != true ] && ok "Manifest valid"; ((pass++))
      _doctor_add_check "manifest" "Manifest valid" "pass"
    else
      [ "$json_output" != true ] && forge_fail "Manifest validation failed"; ((failures++))
      _doctor_add_check "manifest" "Manifest valid" "fail"
    fi

    # Version check
    local installed_version source_version
    installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
    source_version="$FORGE_VERSION"
    if [ "$installed_version" = "$source_version" ]; then
      [ "$json_output" != true ] && ok "Version $source_version"; ((pass++))
      _doctor_add_check "manifest" "Version match" "pass"
    else
      [ "$json_output" != true ] && warn "Version mismatch: installed=$installed_version source=$source_version"; ((warnings++))
      _doctor_add_check "manifest" "Version match" "warn" "installed=$installed_version source=$source_version"
    fi

    # Manifest v2 migration check
    local manifest_ver
    manifest_ver=$(jq -r '.manifest_version // 0' "$MANIFEST_FILE" 2>/dev/null)
    if [ "$manifest_ver" -ge 2 ] 2>/dev/null; then
      [ "$json_output" != true ] && ok "Manifest schema v$manifest_ver"; ((pass++))
      _doctor_add_check "manifest" "Manifest schema" "pass"
    else
      [ "$json_output" != true ] && warn "Manifest needs migration (v$manifest_ver → v$MANIFEST_VERSION)"; ((warnings++))
      _doctor_add_check "manifest" "Manifest schema" "warn" "v$manifest_ver needs migration to v$MANIFEST_VERSION"
    fi
  else
    [ "$json_output" != true ] && forge_fail "No manifest found at $MANIFEST_FILE"; ((failures++))
    _doctor_add_check "manifest" "Manifest exists" "fail" "No manifest found at $MANIFEST_FILE"
  fi

  # ── File Integrity ─────────────────────────────────────────
  [ "$json_output" != true ] && step "File Integrity"

  local file_pass=0
  local file_issues=0
  local file_missing=0
  local file_modified=0

  # Rules
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    local src="$FORGE_SOURCE_DIR/templates/rules/${rule}.md"
    local dst="$CLAUDE_DIR/rules/${rule}.md"
    if [ ! -f "$dst" ]; then
      [ "$json_output" != true ] && forge_fail "Missing: rules/${rule}.md"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      [ "$json_output" != true ] && warn "Modified: rules/${rule}.md"; ((warnings++)); ((file_issues++)); ((file_modified++))
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
      [ "$json_output" != true ] && forge_fail "Missing: hooks/${hook}.sh"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ ! -x "$dst" ]; then
      [ "$json_output" != true ] && forge_fail "Not executable: hooks/${hook}.sh"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      [ "$json_output" != true ] && warn "Modified: hooks/${hook}.sh"; ((warnings++)); ((file_issues++)); ((file_modified++))
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
      [ "$json_output" != true ] && forge_fail "Missing: scripts/${script}.sh"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      [ "$json_output" != true ] && warn "Modified: scripts/${script}.sh"; ((warnings++)); ((file_issues++)); ((file_modified++))
    else
      ((pass++)); ((file_pass++))
    fi
  done < <(forge_shipped_scripts)

  # Root files
  for file in statusline-command.sh; do
    local src="$FORGE_SOURCE_DIR/$file"
    local dst="$CLAUDE_DIR/$file"
    if [ ! -f "$dst" ]; then
      [ "$json_output" != true ] && forge_fail "Missing: $file"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      [ "$json_output" != true ] && warn "Modified: $file"; ((warnings++)); ((file_issues++)); ((file_modified++))
    else
      ((pass++)); ((file_pass++))
    fi
  done

  # Lib files
  for file in "${FORGE_LIB_FILES[@]}"; do
    local src="$FORGE_SOURCE_DIR/lib/$file"
    local dst="$CLAUDE_DIR/lib/$file"
    if [ ! -f "$dst" ]; then
      [ "$json_output" != true ] && forge_fail "Missing: lib/$file"; ((failures++)); ((file_issues++)); ((file_missing++))
    elif [ -f "$src" ] && ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      [ "$json_output" != true ] && warn "Modified: lib/$file"; ((warnings++)); ((file_issues++)); ((file_modified++))
    else
      ((pass++)); ((file_pass++))
    fi
  done

  if [ "$file_issues" -eq 0 ]; then
    [ "$json_output" != true ] && ok "$file_pass files verified"
    _doctor_add_check "files" "File integrity" "pass" "$file_pass files verified"
  else
    if [ "$file_missing" -gt 0 ]; then
      _doctor_add_check "files" "File integrity" "fail" "$file_missing missing, $file_modified modified"
    else
      _doctor_add_check "files" "File integrity" "warn" "$file_modified modified"
    fi
  fi

  # ── Hook Configuration ─────────────────────────────────────
  [ "$json_output" != true ] && step "Hook Configuration"

  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local hooks_ok=true
    while IFS= read -r hook_name; do
      [ -n "$hook_name" ] || continue
      if jq -e --arg cmd "$hook_name" '
        [.hooks[][] | .hooks[]?.command // empty] | any(contains($cmd))
      ' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
        ((pass++))
      else
        [ "$json_output" != true ] && warn "Hook not configured: $hook_name"; ((warnings++))
        hooks_ok=false
      fi
    done < <(forge_shipped_hooks)
    if [ "$hooks_ok" = true ]; then
      [ "$json_output" != true ] && ok "All hooks configured"
      _doctor_add_check "hooks" "Hook configuration" "pass"
    else
      _doctor_add_check "hooks" "Hook configuration" "warn" "Some hooks not configured"
    fi
  else
    [ "$json_output" != true ] && forge_fail "settings.json missing — cannot check hooks"; ((failures++))
    _doctor_add_check "hooks" "Hook configuration" "fail" "settings.json missing"
  fi

  # ── CLAUDE.md Freshness ────────────────────────────────────
  [ "$json_output" != true ] && step "CLAUDE.md"

  if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    local temp_md
    temp_md="$(get_temp_dir)/claude-forge-doctor-check.md"
    if assemble_claude_md "$CLAUDE_DIR/profile.json" "$temp_md" 2>/dev/null; then
      if diff -q <(tail -n +2 "$temp_md") <(tail -n +2 "$CLAUDE_DIR/CLAUDE.md") >/dev/null 2>&1; then
        local md_lines
        md_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
        [ "$json_output" != true ] && ok "Matches profile ($md_lines lines)"; ((pass++))
        _doctor_add_check "claude_md" "CLAUDE.md freshness" "pass"
      else
        [ "$json_output" != true ] && warn "CLAUDE.md differs from current profile — run 'forge switch $(jq -r .persona "$CLAUDE_DIR/profile.json")' to refresh"
        ((warnings++))
        _doctor_add_check "claude_md" "CLAUDE.md freshness" "warn" "Differs from current profile"
      fi
      rm -f "$temp_md"
    else
      [ "$json_output" != true ] && forge_fail "Could not assemble CLAUDE.md for comparison"; ((failures++))
      _doctor_add_check "claude_md" "CLAUDE.md freshness" "fail" "Could not assemble for comparison"
    fi
  else
    [ "$json_output" != true ] && forge_fail "profile.json or CLAUDE.md missing"; ((failures++))
    _doctor_add_check "claude_md" "CLAUDE.md freshness" "fail" "profile.json or CLAUDE.md missing"
  fi

  # ── Plugin Status ──────────────────────────────────────────
  [ "$json_output" != true ] && step "Plugins"

  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local installed_group="full"
    if [ -f "$MANIFEST_FILE" ]; then
      installed_group=$(jq -r '.plugin_group // "full"' "$MANIFEST_FILE" 2>/dev/null)
    fi

    local expected_plugins expected_count actual_count
    expected_plugins=$(resolve_plugin_list "$installed_group" 2>/dev/null)
    expected_count=$(echo "$expected_plugins" | grep -c . || true)
    actual_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)

    # NOTE: permissive >= comparison is intentional pending 1.4.0. The template
    # statically enables the 'full' set regardless of the installed group, so a
    # minimal/standard install reports more enabled than expected. When 1.4.0
    # makes enabledPlugins group-derived, switch this to a set-membership check
    # (actual enabled vs the expected group) rather than a bare count.
    if [ "$actual_count" -ge "$expected_count" ]; then
      [ "$json_output" != true ] && ok "$actual_count plugins enabled (group: $installed_group)"; ((pass++))
      _doctor_add_check "plugins" "Plugins enabled" "pass" "$actual_count plugins (group: $installed_group)"
    elif [ "$actual_count" -gt 0 ]; then
      [ "$json_output" != true ] && warn "$actual_count/$expected_count plugins enabled (group: $installed_group)"; ((warnings++))
      _doctor_add_check "plugins" "Plugins enabled" "warn" "$actual_count/$expected_count (group: $installed_group)"
    else
      [ "$json_output" != true ] && forge_fail "No plugins enabled"; ((failures++))
      _doctor_add_check "plugins" "Plugins enabled" "fail" "No plugins enabled"
    fi
  fi

  # ── CLI ────────────────────────────────────────────────────
  [ "$json_output" != true ] && step "CLI"

  if [ -L "$CLAUDE_DIR/bin/forge" ]; then
    local link_target
    link_target=$(readlink "$CLAUDE_DIR/bin/forge" 2>/dev/null || echo "")
    if [ -x "$link_target" ]; then
      [ "$json_output" != true ] && ok "forge symlink OK"; ((pass++))
      _doctor_add_check "cli" "CLI symlink" "pass"
    else
      [ "$json_output" != true ] && warn "forge symlink target not executable: $link_target"; ((warnings++))
      _doctor_add_check "cli" "CLI symlink" "warn" "Target not executable: $link_target"
    fi
  elif [ -f "$CLAUDE_DIR/bin/forge" ]; then
    if is_windows 2>/dev/null; then
      [ "$json_output" != true ] && ok "forge installed (copy)"; ((pass++))
      _doctor_add_check "cli" "CLI installed" "pass"
    else
      [ "$json_output" != true ] && warn "forge exists but is not a symlink (may become stale)"; ((warnings++))
      _doctor_add_check "cli" "CLI installed" "warn" "Not a symlink (may become stale)"
    fi
  else
    [ "$json_output" != true ] && info "forge not installed at ~/.claude/bin/forge"
  fi

  # ── Project Context (if in a project with .claude/) ───────
  [ "$json_output" != true ] && _doctor_check_project_context

  # ── Output ──────────────────────────────────────────────────
  if [ "$json_output" = true ]; then
    jq -n \
      --argjson checks "$json_checks" \
      --argjson pass "$pass" \
      --argjson warnings "$warnings" \
      --argjson failures "$failures" \
      '{
        schema_version: 1,
        checks: $checks,
        summary: {pass: $pass, warnings: $warnings, failures: $failures}
      }'
    return 0
  fi

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

# ── Project Context Check ──────────────────────────────────
# If doctor is run from a directory with .claude/, show document chain status.

_doctor_check_project_context() {
  local project_claude_dir="$(pwd)/.claude"

  # Only show if we're in a project with .claude/ (forge init was run)
  [ -d "$project_claude_dir" ] || return 0
  # Don't show for the global ~/.claude directory itself
  [ "$(pwd)" = "$HOME" ] && return 0

  step "Project Context"

  if [ -f "$project_claude_dir/CLAUDE.md" ]; then
    ok "CLAUDE.md present"; ((pass++))
  else
    info "No project CLAUDE.md — run 'forge init' to create"
  fi

  # Document chain status
  if [ -f "$project_claude_dir/.docchain-skip" ]; then
    info "Document chain: dismissed (forge init --docs to reconsider)"
    return 0
  fi

  local doc_count=0
  for doc in PROJECT.md REQUIREMENTS.md ROADMAP.md; do
    if [ -f "$(pwd)/$doc" ]; then
      ok "$doc"; ((pass++)); ((doc_count++))
    else
      info "No $doc (recommended for multi-session work)"
    fi
  done

  if [ "$doc_count" -eq 0 ]; then
    info "Run 'forge init --docs' to scaffold, or --skip-docs to dismiss"
  fi
}
