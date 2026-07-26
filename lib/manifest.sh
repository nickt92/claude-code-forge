#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Manifest — manifest CRUD, snapshot, migration, and validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/manifest.sh
#
# Public API:
#   snapshot_pre_install_state  — first-install backup + manifest creation
#   update_manifest_installed   — record installed files + settings diff
#   migrate_legacy_backups      — move .backup-* files into forge-backup/
#   has_legacy_backups          — check if legacy .backup-* files exist
#   validate_manifest           — check manifest integrity
#
# All internal helpers are prefixed _manifest_.

FORGE_VERSION="${FORGE_VERSION:-1.5.0}"
MANIFEST_VERSION=2
BACKUP_DIR="${CLAUDE_DIR}/forge-backup"
MANIFEST_FILE="${BACKUP_DIR}/manifest.json"

# ── UI functions (fallback to ui.sh if not already loaded) ──
command -v ok >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# ── Internal helpers ─────────────────────────────────────────

# Copy a file preserving permissions, warn on symlinks
_manifest_copy_file() {
  local src="$1" dst="$2"
  if [ -L "$src" ]; then
    warn "Symlink detected: $src (copying target, not link)"
  fi
  cp -p "$src" "$dst"
}

# List files in a directory as a JSON array of basenames
_manifest_inventory_dir() {
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

# Record what forge added to settings.json.
#
# Ownership is DECLARED, not inferred. It used to be computed as
# "everything in current that is not in the backup", but the backup is frozen
# at first install (see snapshot_pre_install_state), so any hook or plugin the
# user added afterwards was indistinguishable from a forge addition — forge
# claimed it, and uninstall deleted it. That is data loss in the one file this
# tool exists to edit carefully.
#
# An entry is forge's only if forge actually ships it (it appears in the
# template forge just installed) AND the user did not already have it before
# the first install (it is absent from the backup). Anything else is the
# user's, and is neither claimed nor removed.
#
# An entry forge shipped in an older version but no longer ships is left
# unclaimed rather than deleted. That leaks an orphan, which forge doctor can
# report; over-claiming would destroy user data, so orphans are the safer
# direction.
#
# Args:
#   $1 — current settings.json
#   $2 — backup settings.json (pre-install state; may not exist)
#   $3 — template settings.json forge installs from
_manifest_capture_settings_diff() {
  local current="$1"
  local backup="$2"
  local template="$3"

  # Without a template there is nothing to attribute ownership from. Claiming
  # everything is what caused the data loss, so claim nothing instead — but say
  # so, because the consequence is that uninstall will leave forge's own
  # settings entries behind rather than removing them.
  if [ ! -f "$template" ]; then
    warn "Cannot attribute settings ownership: template not found at ${template:-<unset>}" >&2
    warn "  Uninstall will leave forge's settings entries in place. Re-run forge install to repair." >&2
    echo '{}'
    return
  fi

  local backup_arg="$backup"
  if [ ! -f "$backup" ]; then
    backup_arg=/dev/null
  fi

  jq -n --slurpfile cur "$current" --slurpfile tpl "$template" \
        --argjson bak "$( [ "$backup_arg" = /dev/null ] && echo '{}' || jq '.' "$backup" )" '
    ($cur[0] // {}) as $c |
    ($tpl[0] // {}) as $t |
    $bak as $b |
    {
      hooks: (
        ($c.hooks // {}) | to_entries | map(
          .key as $event |
          ($t.hooks[$event] // []) as $tpl_hooks |
          ($b.hooks[$event] // []) as $bak_hooks |
          {
            key: $event,
            value: (.value | map(
              select(
                .hooks[0].command as $cmd |
                ($tpl_hooks | map(.hooks[0].command) | index($cmd)) != null and
                ($bak_hooks | map(.hooks[0].command) | index($cmd)) == null
              )
            ))
          }
        ) | map(select(.value | length > 0)) | from_entries
      ),
      enabledPlugins: (
        (($t.enabledPlugins // {}) | to_entries) |
        map(select(
          .key as $k |
          (($c.enabledPlugins // {})[$k] != null) and
          (($b.enabledPlugins // {})[$k] == null)
        )) | from_entries
      ),
      statusLine: (
        if ($t | has("statusLine")) and (($b | has("statusLine")) | not)
        then ($c.statusLine // null) else null end
      ),
      alwaysThinkingEnabled: (
        if ($t | has("alwaysThinkingEnabled")) and (($b | has("alwaysThinkingEnabled")) | not)
        then ($c.alwaysThinkingEnabled // null) else null end
      )
    } | with_entries(select(.value != null and .value != {} and .value != []))
  '
}

# ── Migration ────────────────────────────────────────────────

# Migrate a v1 manifest to v2. Idempotent — no-op if already v2.
manifest_migrate_v1_to_v2() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    return 0
  fi

  local version
  version=$(jq -r '.manifest_version // 0' "$MANIFEST_FILE" 2>/dev/null)

  if [ "$version" -ge 2 ] 2>/dev/null; then
    return 0
  fi

  if [ "$version" -ne 1 ] 2>/dev/null; then
    return 1
  fi

  local tmp_manifest="${MANIFEST_FILE}.tmp"
  jq '. +
    {
      manifest_version: 2,
      source_dir: (.source_dir // null),
      plugin_group: (.plugin_group // null)
    }' "$MANIFEST_FILE" > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST_FILE"
}

# ── Settings history ─────────────────────────────────────────
# snapshot_pre_install_state keeps exactly one backup, taken at first install
# and never refreshed. That is the right semantics for "what did the user have
# before forge existed", but it means a user who has been installed for a year
# has a single restore point from a year ago. Every operation that rewrites
# settings.json takes its own timestamped copy here, so `forge restore` can go
# back one step rather than all the way to the beginning.

SETTINGS_HISTORY_DIR="${BACKUP_DIR}/history"
SETTINGS_HISTORY_KEEP="${SETTINGS_HISTORY_KEEP:-20}"

# Copy the current settings.json into the history, labelled with the operation.
# Args: $1 — short label, e.g. "install", "permissions", "uninstall"
snapshot_settings_history() {
  local label="${1:-manual}"
  local settings="$CLAUDE_DIR/settings.json"
  [ -f "$settings" ] || return 0

  # Sanitised so the label can never escape the directory.
  label="${label//[^a-zA-Z0-9_-]/_}"

  mkdir -p "$SETTINGS_HISTORY_DIR" || return 0

  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  local dest="$SETTINGS_HISTORY_DIR/settings-${stamp}-${label}.json"

  # Two operations inside the same second would otherwise overwrite each other.
  local n=1
  while [ -e "$dest" ]; do
    dest="$SETTINGS_HISTORY_DIR/settings-${stamp}-${label}.${n}.json"
    n=$(( n + 1 ))
  done

  cp "$settings" "$dest" 2>/dev/null || return 0
  _prune_settings_history
}

# Keep the most recent $SETTINGS_HISTORY_KEEP snapshots.
_prune_settings_history() {
  [ -d "$SETTINGS_HISTORY_DIR" ] || return 0
  local count
  count=$(find "$SETTINGS_HISTORY_DIR" -name 'settings-*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le "$SETTINGS_HISTORY_KEEP" ] && return 0

  # Names are UTC-stamped, so lexical order is chronological.
  local excess=$(( count - SETTINGS_HISTORY_KEEP ))
  find "$SETTINGS_HISTORY_DIR" -name 'settings-*.json' -type f 2>/dev/null \
    | sort | head -n "$excess" | while IFS= read -r old; do
      rm -f "$old"
    done
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
      _manifest_copy_file "$CLAUDE_DIR/$file" "$BACKUP_DIR/$file"
      pre_existing_files=$(echo "$pre_existing_files" | jq --arg f "$file" '. + {($f): {"backed_up": true}}')
    fi
  done

  # Back up directories
  for dir in rules hooks scripts lib; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
      local dir_files
      dir_files=$(_manifest_inventory_dir "$CLAUDE_DIR/$dir")

      # Only back up if directory has files
      if [ "$(echo "$dir_files" | jq 'length')" -gt 0 ]; then
        mkdir -p "$BACKUP_DIR/$dir"
        for f in "$CLAUDE_DIR/$dir"/*; do
          [ -f "$f" ] && _manifest_copy_file "$f" "$BACKUP_DIR/$dir/$(basename "$f")"
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
      source_dir: null,
      plugin_group: null,
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
# Rewrites the installed file/directory/settings inventory (the file set may
# change between versions) but PRESERVES the permissions ownership record.
#
# That record must survive: only cmd-install's --permissions branch rewrites it,
# and `forge update` reinstalls without that flag. Dropping it here left the
# manifest with no memory of what forge had added, which made the unmerge step
# a no-op on the next preset change — and since merge_permissions is a pure
# union, permissions could then only ever accumulate. Presets stopped being
# switchable, and rules forge had added could never be withdrawn.
#
# Args: persona [source_dir] [plugin_group]
update_manifest_installed() {
  local persona="${1:-}"
  local source_dir="${2:-}"
  local plugin_group="${3:-}"
  # The template forge installs from. Ownership of settings entries is attributed
  # against it — see _manifest_capture_settings_diff. Falls back to
  # FORGE_SOURCE_DIR so the short call form still resolves. Overridable for tests.
  local template_settings="${4:-${source_dir:-${FORGE_SOURCE_DIR:-}}/templates/settings.json}"

  if [ ! -f "$MANIFEST_FILE" ]; then
    forge_fail "No manifest found — cannot record installation"
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
      dir_files=$(_manifest_inventory_dir "$CLAUDE_DIR/$dir")
      installed_dirs=$(echo "$installed_dirs" | jq --arg d "$dir" --argjson files "$dir_files" \
        '. + {($d): $files}')
    fi
  done

  # Capture settings diff
  local settings_additions='{}'
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local backup_settings="$BACKUP_DIR/settings.json"
    settings_additions=$(_manifest_capture_settings_diff \
      "$CLAUDE_DIR/settings.json" "$backup_settings" "$template_settings")
  fi

  # Update manifest — rewrite installed section, update persona + version + v2 fields
  local tmp_manifest="${MANIFEST_FILE}.tmp"
  local pg_arg="null"
  [ -n "$plugin_group" ] && pg_arg="\"$plugin_group\""

  # source_dir is handed to jq as file CONTENT. On Git Bash, MSYS rewrites both
  # argv entries and environment values that look like absolute POSIX paths
  # before a native binary sees them, so the manifest recorded
  # "C:/Program Files/Git/path/to/source". File contents are never rewritten.
  local sd_file="${MANIFEST_FILE}.sd"
  printf '%s' "$source_dir" > "$sd_file"

  jq \
    --rawfile sd "$sd_file" \
    --arg persona "$persona" \
    --arg fv "$FORGE_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson files "$installed_files" \
    --argjson dirs "$installed_dirs" \
    --argjson sa "$settings_additions" \
    --argjson pg "$pg_arg" \
    '.persona = $persona |
     .forge_version = $fv |
     .install_timestamp = $ts |
     .source_dir = (if ($sd | length) == 0 then null else $sd end) |
     .plugin_group = $pg |
     .installed = (
       (
         (.installed // {})
         | with_entries(select(.key == "permissions_preset" or .key == "permissions_added"))
       )
       + {
         files: $files,
         directories: $dirs,
         settings_additions: $sa
       }
     )' "$MANIFEST_FILE" > "$tmp_manifest"
  rm -f "$sd_file"
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
    # NOTE: glob ordering is alphabetical, which matches YYYYMMDD-HHMMSS timestamps
    if [ ! -f "$BACKUP_DIR/$original_name" ]; then
      mkdir -p "$BACKUP_DIR"
      _manifest_copy_file "$backup_file" "$BACKUP_DIR/$original_name"
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
    forge_fail "No forge manifest found at $MANIFEST_FILE"
    return 1
  fi

  # Check it's valid JSON
  if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
    forge_fail "Manifest is not valid JSON"
    return 1
  fi

  # Check required fields
  local version
  version=$(jq -r '.manifest_version // empty' "$MANIFEST_FILE" 2>/dev/null)
  if [ -z "$version" ]; then
    forge_fail "Manifest missing manifest_version field"
    return 1
  fi

  if [ "$version" -lt 1 ] 2>/dev/null || [ "$version" -gt "$MANIFEST_VERSION" ] 2>/dev/null; then
    forge_fail "Unsupported manifest version: $version (expected: 1-$MANIFEST_VERSION)"
    return 1
  fi

  # Check required sections exist
  if ! jq -e '.pre_existing' "$MANIFEST_FILE" >/dev/null 2>&1; then
    forge_fail "Manifest missing pre_existing section"
    return 1
  fi

  if ! jq -e '.installed' "$MANIFEST_FILE" >/dev/null 2>&1; then
    forge_fail "Manifest missing installed section"
    return 1
  fi

  return 0
}
