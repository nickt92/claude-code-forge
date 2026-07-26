#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Uninstall — preview and orchestration for forge removal
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Depends on: lib/manifest.sh (BACKUP_DIR, MANIFEST_FILE, validate_manifest, _manifest_copy_file)
#             lib/settings-unmerge.sh (unmerge_settings)
#             lib/forge-inventory.sh (forge_shipped_rules, forge_shipped_hooks, forge_shipped_scripts)
#             lib/ui.sh (ok, warn, fail)
#
# Usage:
#   source lib/uninstall.sh
#
# Public API:
#   show_uninstall_preview  — print what will be removed/restored
#   uninstall_forge         — restore → remove → cleanup (crash-safe)

# Print what uninstall will do — removal vs restore lists.
show_uninstall_preview() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "No manifest found. Best-effort uninstall will remove known forge files."
    return 0
  fi

  echo ""
  echo -e "${_C_BOLD}Files to remove (forge-installed):${_C_RST}"

  # Individual files
  jq -r '.installed.files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r file; do
    [ -n "$file" ] && echo "  - ~/.claude/$file"
  done

  # Directory files
  jq -r '.installed.directories // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    jq -r --arg d "$dir" '.installed.directories[$d] // [] | .[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r file; do
      [ -n "$file" ] && echo "  - ~/.claude/$dir/$file"
    done
  done

  echo ""
  echo -e "${_C_BOLD}Files to restore (pre-existing):${_C_RST}"

  jq -r '.pre_existing.files // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r file; do
    [ -n "$file" ] && echo "  - ~/.claude/$file"
  done
  if [ "$(jq -r '.pre_existing.files // {} | length' "$MANIFEST_FILE" 2>/dev/null)" -eq 0 ]; then
    echo "  (none)"
  fi

  jq -r '.pre_existing.directories // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    jq -r --arg d "$dir" '.pre_existing.directories[$d].files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null | while IFS= read -r file; do
      [ -n "$file" ] && echo "  - ~/.claude/$dir/$file"
    done
  done

  echo ""
}

# Uninstall forge: restore → remove → cleanup (crash-safe order).
uninstall_forge() {
  # Require jq
  if ! command -v jq >/dev/null 2>&1; then
    forge_fail "jq is required for uninstall. Install: brew install jq (macOS) or apt install jq (Linux)"
    return 1
  fi

  # Best-effort uninstall if no manifest — use forge-inventory for file lists
  if [ ! -f "$MANIFEST_FILE" ]; then
    warn "No manifest found — performing best-effort uninstall"
    for file in "${FORGE_ROOT_FILES[@]}"; do
      rm -f "$CLAUDE_DIR/$file"
    done
    # Remove shipped rules
    while IFS= read -r rule; do
      [ -n "$rule" ] && rm -f "$CLAUDE_DIR/rules/${rule}.md"
    done < <(forge_shipped_rules)
    # Remove shipped hooks
    while IFS= read -r hook; do
      [ -n "$hook" ] && rm -f "$CLAUDE_DIR/hooks/${hook}.sh"
    done < <(forge_shipped_hooks)
    # Remove shipped scripts
    while IFS= read -r script; do
      [ -n "$script" ] && rm -f "$CLAUDE_DIR/scripts/${script}.sh"
    done < <(forge_shipped_scripts)
    # Remove forge lib files
    for file in "${FORGE_LIB_FILES[@]}"; do
      rm -f "$CLAUDE_DIR/lib/$file"
    done
    # Clean empty directories
    for dir in rules hooks scripts lib; do
      [ -d "$CLAUDE_DIR/$dir" ] && rmdir "$CLAUDE_DIR/$dir" 2>/dev/null || true
    done
    ok "Best-effort uninstall complete"
    return 0
  fi

  validate_manifest || return 1

  # ── Phase 1: Restore pre-existing files ──────────────────
  # Individual files
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ -f "$BACKUP_DIR/$file" ]; then
      _manifest_copy_file "$BACKUP_DIR/$file" "$CLAUDE_DIR/$file"
      ok "Restored $file"
    fi
  done < <(jq -r '.pre_existing.files // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null)

  # Directory files
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    if [ -d "$BACKUP_DIR/$dir" ]; then
      mkdir -p "$CLAUDE_DIR/$dir"
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ -f "$BACKUP_DIR/$dir/$file" ]; then
          _manifest_copy_file "$BACKUP_DIR/$dir/$file" "$CLAUDE_DIR/$dir/$file"
          ok "Restored $dir/$file"
        fi
      done < <(jq -r --arg d "$dir" '.pre_existing.directories[$d].files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)
    fi
  done < <(jq -r '.pre_existing.directories // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null)

  # Handle settings.json unmerge — extract forge additions and pass explicitly
  local forge_additions
  forge_additions=$(jq -r '.installed.settings_additions // {}' "$MANIFEST_FILE" 2>/dev/null)
  unmerge_settings "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json" "$forge_additions"

  # ── Phase 2: Remove forge-installed files ────────────────
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Don't remove files we just restored
    if ! jq -e --arg f "$file" '.pre_existing.files[$f]' "$MANIFEST_FILE" >/dev/null 2>&1; then
      rm -f "$CLAUDE_DIR/$file"
    fi
  done < <(jq -r '.installed.files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)

  # Remove forge files from directories
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue

    # Get pre-existing file list for this directory as a newline-separated string
    local pre_dir_files
    pre_dir_files=$(jq -r --arg d "$dir" '.pre_existing.directories[$d].files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)

    while IFS= read -r file; do
      [ -n "$file" ] || continue
      # Only remove if not a pre-existing file (already restored above)
      if ! echo "$pre_dir_files" | grep -qx "$file"; then
        rm -f "$CLAUDE_DIR/$dir/$file"
      fi
    done < <(jq -r --arg d "$dir" '.installed.directories[$d] // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)

    # Remove directory if empty
    if [ -d "$CLAUDE_DIR/$dir" ] && [ -z "$(ls -A "$CLAUDE_DIR/$dir" 2>/dev/null)" ]; then
      rmdir "$CLAUDE_DIR/$dir" 2>/dev/null || true
    fi
  done < <(jq -r '.installed.directories // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null)

  # ── Phase 3: Cleanup ────────────────────────────────────
  rm -rf "$BACKUP_DIR"

  ok "Claude Code Forge uninstalled"
}
