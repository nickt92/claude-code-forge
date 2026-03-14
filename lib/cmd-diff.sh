#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-diff — show differences between source and installed files
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Compares source tree with installed ~/.claude/ files.
#
# Usage:
#   forge diff

cmd_diff() {
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/plugins.sh"
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    printf "\n${_C_BOLD}forge diff${_C_RST} — Show differences between source and installed files\n"
    printf "\n${_C_BOLD}Usage:${_C_RST}\n"
    printf "  forge diff\n"
    return 0
  fi

  banner "Diff"

  local has_diff=false

  # ── Version ────────────────────────────────────────────────
  step "Version"
  local installed_version="unknown"
  if [ -f "$MANIFEST_FILE" ]; then
    installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  fi

  if [ "$installed_version" = "$FORGE_VERSION" ]; then
    ok "Source and installed match: $FORGE_VERSION"
  else
    warn "installed=$installed_version  source=$FORGE_VERSION"
    has_diff=true
  fi

  # ── Rules ──────────────────────────────────────────────────
  step "Rules"
  local rules_diff=false

  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    local src="$FORGE_SOURCE_DIR/templates/rules/${rule}.md"
    local dst="$CLAUDE_DIR/rules/${rule}.md"
    if [ ! -f "$dst" ]; then
      diff_added "${rule}.md (new in source)"
      rules_diff=true
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      diff_changed "${rule}.md"
      rules_diff=true
    fi
  done < <(forge_shipped_rules)

  # Check for removed rules (in installed but not in source)
  if [ -d "$CLAUDE_DIR/rules" ]; then
    for f in "$CLAUDE_DIR/rules/"*.md; do
      [ -f "$f" ] || continue
      local basename_rule
      basename_rule=$(basename "$f" .md)
      if [ ! -f "$FORGE_SOURCE_DIR/templates/rules/${basename_rule}.md" ]; then
        diff_removed "${basename_rule}.md (not in source)"
        rules_diff=true
      fi
    done
  fi

  if [ "$rules_diff" = false ]; then
    ok "No differences"
  else
    has_diff=true
  fi

  # ── Hooks ──────────────────────────────────────────────────
  step "Hooks"
  local hooks_diff=false

  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    local src="$FORGE_SOURCE_DIR/hooks/${hook}.sh"
    local dst="$CLAUDE_DIR/hooks/${hook}.sh"
    if [ ! -f "$dst" ]; then
      diff_added "${hook}.sh (new in source)"
      hooks_diff=true
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      diff_changed "${hook}.sh"
      hooks_diff=true
    fi
  done < <(forge_shipped_hooks)

  if [ "$hooks_diff" = false ]; then
    ok "No differences"
  else
    has_diff=true
  fi

  # ── Scripts ────────────────────────────────────────────────
  step "Scripts"
  local scripts_diff=false

  while IFS= read -r script; do
    [ -n "$script" ] || continue
    local src="$FORGE_SOURCE_DIR/scripts/${script}.sh"
    local dst="$CLAUDE_DIR/scripts/${script}.sh"
    if [ ! -f "$dst" ]; then
      diff_added "${script}.sh (new in source)"
      scripts_diff=true
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      diff_changed "${script}.sh"
      scripts_diff=true
    fi
  done < <(forge_shipped_scripts)

  if [ "$scripts_diff" = false ]; then
    ok "No differences"
  else
    has_diff=true
  fi

  # ── Root Files ─────────────────────────────────────────────
  step "Root Files"
  local root_diff=false

  for file in statusline-command.sh; do
    local src="$FORGE_SOURCE_DIR/$file"
    local dst="$CLAUDE_DIR/$file"
    if [ ! -f "$dst" ]; then
      diff_added "$file (new in source)"
      root_diff=true
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      diff_changed "$file"
      root_diff=true
    fi
  done

  if [ "$root_diff" = false ]; then
    ok "No differences"
  else
    has_diff=true
  fi

  # ── Lib Files ──────────────────────────────────────────────
  step "Lib Files"
  local lib_diff=false

  for file in "${FORGE_LIB_FILES[@]}"; do
    local src="$FORGE_SOURCE_DIR/lib/$file"
    local dst="$CLAUDE_DIR/lib/$file"
    if [ ! -f "$dst" ]; then
      diff_added "lib/$file (new in source)"
      lib_diff=true
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      diff_changed "lib/$file"
      lib_diff=true
    fi
  done

  if [ "$lib_diff" = false ]; then
    ok "No differences"
  else
    has_diff=true
  fi

  # ── CLAUDE.md ──────────────────────────────────────────────
  step "CLAUDE.md"

  if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    local temp_md
    temp_md="$(get_temp_dir)/claude-forge-diff-check.md"
    if assemble_claude_md "$CLAUDE_DIR/profile.json" "$temp_md" 2>/dev/null; then
      local src_lines dst_lines
      src_lines=$(wc -l < "$temp_md" | tr -d ' ')
      dst_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')

      if diff -q <(tail -n +2 "$temp_md") <(tail -n +2 "$CLAUDE_DIR/CLAUDE.md") >/dev/null 2>&1; then
        ok "Matches profile ($dst_lines lines)"
      else
        diff_changed "CLAUDE.md (source: $src_lines lines, installed: $dst_lines lines)"
        has_diff=true
      fi
      rm -f "$temp_md"
    fi
  else
    warn "Cannot compare — profile.json or CLAUDE.md missing"
  fi

  # ── Summary ────────────────────────────────────────────────
  echo ""
  if [ "$has_diff" = false ]; then
    ok "No differences found"
  else
    info "Run 'forge update' or 'forge install' to sync"
  fi
}
