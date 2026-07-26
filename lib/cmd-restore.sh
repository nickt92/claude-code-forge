#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-restore — roll settings.json back to an earlier snapshot
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Every forge operation that rewrites settings.json first copies it into
# ~/.claude/forge-backup/history/. This command lists those copies and puts
# one back. It is the undo for a merge that went wrong.
#
# Required commands:
#   jq
#
# Usage:
#   forge restore --list                 # show available snapshots
#   forge restore <snapshot>             # restore by name or timestamp
#   forge restore --latest               # restore the most recent snapshot
#   forge restore --pre-install          # restore the original pre-forge backup

# Newest last, so the most recent is easy to pick off the end.
_restore_snapshots() {
  [ -d "$SETTINGS_HISTORY_DIR" ] || return 0
  find "$SETTINGS_HISTORY_DIR" -name 'settings-*.json' -type f 2>/dev/null | sort
}

# Turn settings-20260726T101500Z-install.json into "2026-07-26 10:15:00 UTC  install"
_restore_describe() {
  local base
  base=$(basename "$1")
  local stamp="${base#settings-}"
  stamp="${stamp%%-*}"
  local label="${base#settings-*-}"
  label="${label%.json}"
  label="${label%.[0-9]}"

  local y="${stamp:0:4}" mo="${stamp:4:2}" d="${stamp:6:2}"
  local h="${stamp:9:2}" mi="${stamp:11:2}" s="${stamp:13:2}"
  printf "%s-%s-%s %s:%s:%s UTC  %s" "$y" "$mo" "$d" "$h" "$mi" "$s" "$label"
}

_restore_list() {
  local settings="$CLAUDE_DIR/settings.json"
  banner "Settings History"

  local pre_install="$BACKUP_DIR/settings.json"
  if [ -f "$pre_install" ]; then
    printf "\n  ${_C_BOLD}--pre-install${_C_RST}  %s\n" "$(_restore_describe_pre_install "$pre_install")"
    info "  Your settings.json from before forge was first installed"
  fi

  local snapshots
  snapshots=$(_restore_snapshots)

  if [ -z "$snapshots" ]; then
    printf "\n"
    info "No operation snapshots yet. They are written each time forge changes settings.json."
    return 0
  fi

  printf "\n  ${_C_DIM}Snapshots taken before each operation, newest last:${_C_RST}\n\n"
  while IFS= read -r snap; do
    [ -n "$snap" ] || continue
    local marker="  "
    if [ -f "$settings" ] && cmp -s "$snap" "$settings"; then
      marker="${_C_GREEN}=${_C_RST} "
    fi
    printf "  %s%-42s %s\n" "$marker" "$(basename "$snap")" "$(_restore_describe "$snap")"
  done <<< "$snapshots"

  printf "\n"
  info "= marks a snapshot identical to your current settings.json"
  info "Restore with: forge restore <name>   (or --latest)"
}

_restore_describe_pre_install() {
  local f="$1"
  local when="unknown date"
  if [ -f "$MANIFEST_FILE" ]; then
    when=$(jq -r '.install_timestamp // "unknown date"' "$MANIFEST_FILE" 2>/dev/null)
  fi
  printf "taken %s" "$when"
}

# Put a snapshot back, taking a snapshot of the current state first so the
# restore itself is undoable.
_restore_apply() {
  local source_file="$1"
  local description="$2"
  local assume_yes="$3"
  local settings="$CLAUDE_DIR/settings.json"

  if [ ! -f "$source_file" ]; then
    forge_fail "Snapshot not found: $source_file"
    return 1
  fi

  if ! jq -e '.' "$source_file" >/dev/null 2>&1; then
    forge_fail "Snapshot is not valid JSON — refusing to restore it: $(basename "$source_file")"
    return 1
  fi

  if [ -f "$settings" ] && cmp -s "$source_file" "$settings"; then
    ok "Already identical to $description — nothing to do."
    return 0
  fi

  printf "\n"
  kv "Restoring" "$description"
  kv "Into" "$settings"

  if [ -f "$settings" ]; then
    local before after
    before=$(jq -r '[paths(scalars)] | length' "$settings" 2>/dev/null || echo "?")
    after=$(jq -r '[paths(scalars)] | length' "$source_file" 2>/dev/null || echo "?")
    kv "Settings entries" "$before → $after"
  fi

  if [ "$assume_yes" != true ]; then
    printf "\n"
    read -r -p "  Replace your current settings.json? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) info "Cancelled — nothing changed."; return 0 ;;
    esac
  fi

  # The restore is itself an operation, so it gets its own snapshot. Without
  # this, restoring the wrong thing would be unrecoverable.
  snapshot_settings_history "pre-restore"

  cp "$source_file" "${settings}.tmp" || { forge_fail "Could not write ${settings}.tmp"; return 1; }
  mv "${settings}.tmp" "$settings" || { forge_fail "Could not replace $settings"; return 1; }

  ok "Restored. Your previous settings.json was snapshotted first."
  info "Run 'forge doctor' to check the result, or 'forge restore --list' to step back again."
}

_restore_help() {
  printf "\n${_C_BOLD}forge restore${_C_RST} — roll settings.json back to an earlier snapshot\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge restore --list             Show available snapshots\n"
  printf "  forge restore <name>             Restore a snapshot by filename or timestamp\n"
  printf "  forge restore --latest           Restore the most recent snapshot\n"
  printf "  forge restore --pre-install      Restore your settings from before forge\n"
  printf "\n${_C_BOLD}Options:${_C_RST}\n"
  printf "  --yes                            Skip the confirmation prompt\n"
  printf "\n${_C_DIM}A snapshot is taken automatically before every forge operation that\n"
  printf "rewrites settings.json, and before a restore itself.${_C_RST}\n"
}

cmd_restore() {
  # BACKUP_DIR, MANIFEST_FILE, SETTINGS_HISTORY_DIR and snapshot_settings_history
  # all live in manifest.sh. The dispatcher sources only ui.sh and this file, so
  # without this the history directory resolves to "/history" and every snapshot
  # is invisible.
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  local target="" assume_yes=false mode=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --list|-l)     mode="list"; shift ;;
      --latest)      mode="latest"; shift ;;
      --pre-install) mode="pre-install"; shift ;;
      --yes|-y)      assume_yes=true; shift ;;
      --help|-h)     _restore_help; return 0 ;;
      -*)            forge_fail "Unknown option: $1"; _restore_help; return 1 ;;
      *)             target="$1"; shift ;;
    esac
  done

  if [ ! -d "$BACKUP_DIR" ]; then
    forge_fail "Forge is not installed (no backup directory at $BACKUP_DIR)"
    return 1
  fi

  case "$mode" in
    list)
      _restore_list
      return 0
      ;;
    latest)
      local newest
      newest=$(_restore_snapshots | tail -1)
      if [ -z "$newest" ]; then
        forge_fail "No snapshots available yet"
        return 1
      fi
      _restore_apply "$newest" "$(_restore_describe "$newest")" "$assume_yes"
      return
      ;;
    pre-install)
      _restore_apply "$BACKUP_DIR/settings.json" \
        "your pre-forge settings ($(_restore_describe_pre_install "$BACKUP_DIR/settings.json"))" \
        "$assume_yes"
      return
      ;;
  esac

  if [ -z "$target" ]; then
    _restore_help
    return 0
  fi

  # Accept a bare filename, a full path, or just the timestamp.
  local candidate=""
  if [ -f "$target" ]; then
    candidate="$target"
  elif [ -f "$SETTINGS_HISTORY_DIR/$target" ]; then
    candidate="$SETTINGS_HISTORY_DIR/$target"
  else
    local matches
    matches=$(_restore_snapshots | grep -F "$target" || true)
    local match_count
    match_count=$(printf '%s' "$matches" | grep -c . || true)
    if [ "${match_count:-0}" -eq 0 ]; then
      forge_fail "No snapshot matching: $target"
      info "Run 'forge restore --list' to see what is available."
      return 1
    elif [ "${match_count:-0}" -gt 1 ]; then
      forge_fail "Ambiguous — $match_count snapshots match '$target':"
      printf '%s\n' "$matches" | while IFS= read -r m; do
        [ -n "$m" ] && info "  $(basename "$m")"
      done
      return 1
    fi
    candidate="$matches"
  fi

  _restore_apply "$candidate" "$(_restore_describe "$candidate")" "$assume_yes"
}
