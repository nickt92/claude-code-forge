#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Backup & Restore — manifest-based backup system for Claude Code Forge
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/backup.sh
#
# Public API:
#   snapshot_pre_install_state  — first-install backup + manifest creation
#   update_manifest_installed   — record installed files + settings diff
#   migrate_legacy_backups      — move .backup-* files into forge-backup/
#   validate_manifest           — check manifest integrity
#   show_uninstall_preview      — print what will be removed/restored
#   uninstall_forge             — restore → remove → cleanup (crash-safe)
#
# All internal helpers are prefixed _backup_.

FORGE_VERSION="${FORGE_VERSION:-0.1.0}"
MANIFEST_VERSION=1
BACKUP_DIR="${CLAUDE_DIR}/forge-backup"
MANIFEST_FILE="${BACKUP_DIR}/manifest.json"

# ── UI functions (fallback to ui.sh if not already loaded) ──
command -v ok >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# ── Internal helpers ─────────────────────────────────────────

# Copy a file preserving permissions, warn on symlinks
_backup_copy_file() {
  local src="$1" dst="$2"
  if [ -L "$src" ]; then
    warn "Symlink detected: $src (copying target, not link)"
  fi
  cp -p "$src" "$dst"
}

# List files in a directory as a JSON array of basenames
_backup_inventory_dir() {
  local dir="$1"
  local files=()
  if [ -d "$dir" ]; then
    for f in "$dir"/*; do
      [ -f "$f" ] && files+=("$(basename "$f")")
    done
  fi
  if [ ${#files[@]} -eq 0 ]; then
    echo '[]'
    return
  fi
  printf '%s\n' "${files[@]}" | jq -R . | jq -s .
}

# Compute what forge added to settings.json by diffing current vs backup
_backup_capture_settings_diff() {
  local current="$1"
  local backup="$2"

  if [ ! -f "$backup" ]; then
    # No backup means everything in current is forge-installed
    cat "$current"
    return
  fi

  # Extract the forge-specific additions
  jq -n --slurpfile cur "$current" --slurpfile bak "$backup" '
    ($cur[0] // {}) as $c |
    ($bak[0] // {}) as $b |
    {
      hooks: (
        ($c.hooks // {}) | to_entries | map(
          .key as $event |
          .value as $cur_hooks |
          ($b.hooks[$event] // []) as $bak_hooks |
          {
            key: $event,
            value: ($cur_hooks | map(
              select(
                .hooks[0].command as $cmd |
                ($bak_hooks | map(.hooks[0].command) | index($cmd)) == null
              )
            ))
          }
        ) | map(select(.value | length > 0)) | from_entries
      ),
      enabledPlugins: (
        (($c.enabledPlugins // {}) | to_entries) |
        map(select(
          .key as $k | ($b.enabledPlugins // {})[$k] == null
        )) | from_entries
      ),
      statusLine: ($c.statusLine // null),
      alwaysThinkingEnabled: ($c.alwaysThinkingEnabled // null)
    } | with_entries(select(.value != null and .value != {} and .value != []))
  '
}

# ── Public API ───────────────────────────────────────────────

# Snapshot pre-existing state before first install.
# No-op if manifest already exists (re-install preserves original backup).
snapshot_pre_install_state() {
  # Skip on re-install — pre_existing must stay frozen
  if [ -f "$MANIFEST_FILE" ]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"

  local pre_existing_files='{}'
  local pre_existing_dirs='{}'

  # Back up individual files
  for file in CLAUDE.md settings.json profile.json statusline-command.sh; do
    if [ -f "$CLAUDE_DIR/$file" ]; then
      _backup_copy_file "$CLAUDE_DIR/$file" "$BACKUP_DIR/$file"
      pre_existing_files=$(echo "$pre_existing_files" | jq --arg f "$file" '. + {($f): {"backed_up": true}}')
    fi
  done

  # Back up directories
  for dir in rules hooks scripts lib; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
      local dir_files
      dir_files=$(_backup_inventory_dir "$CLAUDE_DIR/$dir")

      # Only back up if directory has files
      if [ "$(echo "$dir_files" | jq 'length')" -gt 0 ]; then
        mkdir -p "$BACKUP_DIR/$dir"
        for f in "$CLAUDE_DIR/$dir"/*; do
          [ -f "$f" ] && _backup_copy_file "$f" "$BACKUP_DIR/$dir/$(basename "$f")"
        done
        pre_existing_dirs=$(echo "$pre_existing_dirs" | jq --arg d "$dir" --argjson files "$dir_files" \
          '. + {($d): {"backed_up": true, "files": $files}}')
      fi
    fi
  done

  # Write initial manifest (atomic: write to tmp, then mv)
  local tmp_manifest="${MANIFEST_FILE}.tmp"
  jq -n \
    --argjson mv "$MANIFEST_VERSION" \
    --arg fv "$FORGE_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson pf "$pre_existing_files" \
    --argjson pd "$pre_existing_dirs" \
    '{
      manifest_version: $mv,
      forge_version: $fv,
      install_timestamp: $ts,
      persona: null,
      migrated_from_legacy: false,
      pre_existing: {
        files: $pf,
        directories: $pd
      },
      installed: {
        files: [],
        directories: {},
        settings_additions: {}
      }
    }' > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST_FILE"
}

# Record what forge installed. Called after install completes.
# Rewrites the installed section entirely (file set may change between versions).
update_manifest_installed() {
  local persona="${1:-}"

  if [ ! -f "$MANIFEST_FILE" ]; then
    return 1
  fi

  # Inventory installed files
  local installed_files='[]'
  for file in CLAUDE.md profile.json statusline-command.sh; do
    if [ -f "$CLAUDE_DIR/$file" ]; then
      installed_files=$(echo "$installed_files" | jq --arg f "$file" '. + [$f]')
    fi
  done

  # Inventory installed directories
  local installed_dirs='{}'
  for dir in rules hooks scripts lib; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
      local dir_files
      dir_files=$(_backup_inventory_dir "$CLAUDE_DIR/$dir")
      installed_dirs=$(echo "$installed_dirs" | jq --arg d "$dir" --argjson files "$dir_files" \
        '. + {($d): $files}')
    fi
  done

  # Capture settings diff
  local settings_additions='{}'
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local backup_settings="$BACKUP_DIR/settings.json"
    settings_additions=$(_backup_capture_settings_diff "$CLAUDE_DIR/settings.json" "$backup_settings")
  fi

  # Update manifest — rewrite installed section, update persona + version
  local tmp_manifest="${MANIFEST_FILE}.tmp"
  jq \
    --arg persona "$persona" \
    --arg fv "$FORGE_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson files "$installed_files" \
    --argjson dirs "$installed_dirs" \
    --argjson sa "$settings_additions" \
    '.persona = $persona |
     .forge_version = $fv |
     .install_timestamp = $ts |
     .installed = {
       files: $files,
       directories: $dirs,
       settings_additions: $sa
     }' "$MANIFEST_FILE" > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST_FILE"
}

# Migrate legacy .backup-* files into forge-backup/.
# Finds the oldest backup for each file type and moves it.
migrate_legacy_backups() {
  if [ ! -d "$CLAUDE_DIR" ]; then
    return 0
  fi

  # Check if already migrated
  if [ -f "$MANIFEST_FILE" ] && jq -e '.migrated_from_legacy == true' "$MANIFEST_FILE" >/dev/null 2>&1; then
    return 0
  fi

  local found_legacy=false

  for backup_file in "$CLAUDE_DIR"/*.backup-*; do
    [ -f "$backup_file" ] || continue
    found_legacy=true

    local basename_full
    basename_full=$(basename "$backup_file")
    # Extract original filename: everything before .backup-TIMESTAMP
    local original_name="${basename_full%%.backup-*}"

    # Keep oldest backup only — move to forge-backup/
    if [ ! -f "$BACKUP_DIR/$original_name" ]; then
      mkdir -p "$BACKUP_DIR"
      _backup_copy_file "$backup_file" "$BACKUP_DIR/$original_name"
    fi

    # Remove the legacy backup file
    rm -f "$backup_file"
  done

  # Set migrated flag if manifest exists
  if [ -f "$MANIFEST_FILE" ] && [ "$found_legacy" = true ]; then
    local tmp_manifest="${MANIFEST_FILE}.tmp"
    jq '.migrated_from_legacy = true' "$MANIFEST_FILE" > "$tmp_manifest"
    mv "$tmp_manifest" "$MANIFEST_FILE"
  fi
}

# Check if legacy .backup-* files exist
has_legacy_backups() {
  for f in "$CLAUDE_DIR"/*.backup-*; do
    [ -f "$f" ] && return 0
  done
  return 1
}

# Validate manifest structure. Fails fast on corruption.
validate_manifest() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    fail "No forge manifest found at $MANIFEST_FILE"
    return 1
  fi

  # Check it's valid JSON
  if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
    fail "Manifest is not valid JSON"
    return 1
  fi

  # Check required fields
  local version
  version=$(jq -r '.manifest_version // empty' "$MANIFEST_FILE" 2>/dev/null)
  if [ -z "$version" ]; then
    fail "Manifest missing manifest_version field"
    return 1
  fi

  if [ "$version" -ne "$MANIFEST_VERSION" ] 2>/dev/null; then
    fail "Unsupported manifest version: $version (expected: $MANIFEST_VERSION)"
    return 1
  fi

  # Check required sections exist
  if ! jq -e '.pre_existing' "$MANIFEST_FILE" >/dev/null 2>&1; then
    fail "Manifest missing pre_existing section"
    return 1
  fi

  if ! jq -e '.installed' "$MANIFEST_FILE" >/dev/null 2>&1; then
    fail "Manifest missing installed section"
    return 1
  fi

  return 0
}

# Print what uninstall will do — removal vs restore lists.
show_uninstall_preview() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "No manifest found. Best-effort uninstall will remove known forge files."
    return 0
  fi

  echo ""
  echo -e "${BOLD:-}Files to remove (forge-installed):${RST:-}"

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
  echo -e "${BOLD:-}Files to restore (pre-existing):${RST:-}"

  local has_pre_files=false
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
    fail "jq is required for uninstall. Install: brew install jq (macOS) or apt install jq (Linux)"
    return 1
  fi

  # Best-effort uninstall if no manifest
  if [ ! -f "$MANIFEST_FILE" ]; then
    warn "No manifest found — performing best-effort uninstall"
    rm -f "$CLAUDE_DIR/CLAUDE.md"
    rm -f "$CLAUDE_DIR/profile.json"
    rm -f "$CLAUDE_DIR/statusline-command.sh"
    # Remove known forge rule files
    for rule in quality-engineering agent-orchestration commit-and-delivery context-and-memory pull-requests project-setup scope-discipline; do
      rm -f "$CLAUDE_DIR/rules/${rule}.md"
    done
    # Remove known forge hook files
    for hook in session-init architect-gate commit-validator backup-transcript; do
      rm -f "$CLAUDE_DIR/hooks/${hook}.sh"
    done
    # Remove known forge script files
    for script in generate-project-claude init-project-claude; do
      rm -f "$CLAUDE_DIR/scripts/${script}.sh"
    done
    # Remove forge lib files
    rm -f "$CLAUDE_DIR/lib/ui.sh"
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
      _backup_copy_file "$BACKUP_DIR/$file" "$CLAUDE_DIR/$file"
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
          _backup_copy_file "$BACKUP_DIR/$dir/$file" "$CLAUDE_DIR/$dir/$file"
          ok "Restored $dir/$file"
        fi
      done < <(jq -r --arg d "$dir" '.pre_existing.directories[$d].files // [] | .[]' "$MANIFEST_FILE" 2>/dev/null)
    fi
  done < <(jq -r '.pre_existing.directories // {} | keys[]' "$MANIFEST_FILE" 2>/dev/null)

  # Handle settings.json unmerge
  _backup_unmerge_settings

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

# Internal: unmerge settings.json — restore user's original + preserve post-install additions
_backup_unmerge_settings() {
  local current="$CLAUDE_DIR/settings.json"
  local backup="$BACKUP_DIR/settings.json"

  [ -f "$current" ] || return 0

  if [ -f "$backup" ]; then
    # Start from backup, then add any user post-install additions
    local forge_additions
    forge_additions=$(jq -r '.installed.settings_additions // {}' "$MANIFEST_FILE" 2>/dev/null)

    # Find user post-install additions: keys in current that are NOT in backup AND NOT in forge additions
    jq -n \
      --slurpfile cur "$current" \
      --slurpfile bak "$backup" \
      --argjson forge "$forge_additions" \
      '
      ($cur[0] // {}) as $c |
      ($bak[0] // {}) as $b |
      # Start with backup as base
      $b |
      # Add back any user hooks added post-install (not in forge additions)
      .hooks = (
        ($b.hooks // {}) as $bh |
        ($c.hooks // {}) as $ch |
        ($forge.hooks // {}) as $fh |
        # For each event in current hooks
        ($ch | to_entries | map(
          .key as $event |
          .value as $cur_hooks |
          ($bh[$event] // []) as $bak_hooks |
          ($fh[$event] // []) as $forge_hooks |
          # Keep: backup hooks + user post-install hooks (not in forge)
          {
            key: $event,
            value: (
              $bak_hooks + (
                $cur_hooks | map(
                  select(
                    .hooks[0].command as $cmd |
                    ($bak_hooks | map(.hooks[0].command) | index($cmd)) == null and
                    ($forge_hooks | map(.hooks[0].command) | index($cmd)) == null
                  )
                )
              )
            )
          }
        ) | map(select(.value | length > 0)) | from_entries) as $merged_hooks |
        # Include events from backup that were removed from current
        ($bh | to_entries | map(
          select(.key as $k | $merged_hooks[$k] == null)
        ) | from_entries) + $merged_hooks
      ) |
      # Restore plugins: backup + user post-install (not forge)
      .enabledPlugins = (
        ($b.enabledPlugins // {}) + (
          ($c.enabledPlugins // {}) | to_entries |
          map(select(
            .key as $k |
            ($b.enabledPlugins // {})[$k] == null and
            ($forge.enabledPlugins // {})[$k] == null
          )) | from_entries
        )
      ) |
      # Remove forge-specific top-level keys unless they were in backup
      if $b | has("statusLine") then . else del(.statusLine) end |
      if $b | has("alwaysThinkingEnabled") then . else del(.alwaysThinkingEnabled) end
      ' > "${current}.tmp"
    mv "${current}.tmp" "$current"
  else
    # No backup — remove forge hooks by command match, remove forge plugins by key
    local forge_additions
    forge_additions=$(jq -r '.installed.settings_additions // {}' "$MANIFEST_FILE" 2>/dev/null)

    jq -n \
      --slurpfile cur "$current" \
      --argjson forge "$forge_additions" \
      '
      ($cur[0] // {}) as $c |
      $c |
      # Remove forge hooks by command match
      .hooks = (
        ($c.hooks // {}) | to_entries | map(
          .key as $event |
          {
            key: $event,
            value: (
              .value | map(
                select(
                  .hooks[0].command as $cmd |
                  (($forge.hooks[$event] // []) | map(.hooks[0].command) | index($cmd)) == null
                )
              )
            )
          }
        ) | map(select(.value | length > 0)) | from_entries
      ) |
      # Remove forge plugins
      .enabledPlugins = (
        ($c.enabledPlugins // {}) | to_entries |
        map(select(
          .key as $k | ($forge.enabledPlugins // {})[$k] == null
        )) | from_entries
      ) |
      # Remove forge top-level keys
      if ($forge | has("statusLine")) then del(.statusLine) else . end |
      if ($forge | has("alwaysThinkingEnabled")) then del(.alwaysThinkingEnabled) else . end
      ' > "${current}.tmp"
    mv "${current}.tmp" "$current"
  fi
}
