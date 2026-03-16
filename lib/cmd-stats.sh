#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-stats — installation overview, security events, sessions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Read-only command that displays statistics about the forge
# installation, security event history, and session backups.
#
# Usage:
#   forge stats              # all sections
#   forge stats --security   # security section only
#   forge stats --sessions   # sessions section only

# ── Helpers ──────────────────────────────────────────────────

# Convert ISO timestamp to "X days ago"
_stats_days_ago() {
  local timestamp="$1"
  local date_part="${timestamp%%T*}"
  local install_epoch now_epoch
  if install_epoch=$(date -jf "%Y-%m-%d" "$date_part" +%s 2>/dev/null); then
    : # macOS date succeeded
  elif install_epoch=$(date -d "$date_part" +%s 2>/dev/null); then
    : # GNU date succeeded
  else
    echo "$timestamp"
    return
  fi
  now_epoch=$(date +%s)
  local days=$(( (now_epoch - install_epoch) / 86400 ))
  if [ "$days" -eq 0 ]; then
    echo "today"
  elif [ "$days" -eq 1 ]; then
    echo "1 day ago"
  else
    echo "$days days ago"
  fi
}

# ── Sections ─────────────────────────────────────────────────

_stats_installation() {
  step "Installation"

  # Persona
  local persona="unknown" label="unknown"
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    persona=$(jq -r '.persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
    label=$(jq -r '.label // .persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
  fi
  kv "Persona" "$label ($persona)"

  # Version
  local installed_version
  installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  kv "Version" "$installed_version"

  # Plugin group
  local plugin_group
  plugin_group=$(jq -r '.plugin_group // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  local plugin_count
  plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  kv "Plugins" "$plugin_group ($plugin_count enabled)"

  # Install date + age
  local timestamp
  timestamp=$(jq -r '.install_timestamp // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  if [ "$timestamp" != "unknown" ]; then
    local age
    age=$(_stats_days_ago "$timestamp")
    local date_part="${timestamp%%T*}"
    kv "Installed" "$date_part ($age)"
  else
    kv "Installed" "unknown"
  fi

  # Files managed — count from manifest installed section
  local rule_count=0 hook_count=0 script_count=0 other_count=0
  rule_count=$(jq -r '.installed.directories.rules // [] | length' "$MANIFEST_FILE" 2>/dev/null || echo 0)
  hook_count=$(jq -r '.installed.directories.hooks // [] | length' "$MANIFEST_FILE" 2>/dev/null || echo 0)
  script_count=$(jq -r '.installed.directories.scripts // [] | length' "$MANIFEST_FILE" 2>/dev/null || echo 0)
  other_count=$(jq -r '.installed.files // [] | length' "$MANIFEST_FILE" 2>/dev/null || echo 0)
  local total=$(( rule_count + hook_count + script_count + other_count ))
  kv "Files" "$total ($rule_count rules, $hook_count hooks, $script_count scripts, $other_count other)"
}

_stats_security() {
  step "Security Events"

  local security_log="$CLAUDE_DIR/security.log"
  if [ ! -f "$security_log" ] || [ ! -s "$security_log" ]; then
    info "No security events recorded."
    return
  fi

  local total
  total=$(wc -l < "$security_log" | tr -d ' ')
  kv "Total" "$total detections"

  # Most recent event (last line timestamp)
  local last_line
  last_line=$(tail -1 "$security_log")
  local last_ts="${last_line%% *}"
  kv "Most recent" "$last_ts"

  # Count by type — bash 3 compatible (no associative arrays)
  local types_tmp
  types_tmp=$(mktemp)
  # Parse types= quoted field from each line, split on ", "
  while IFS= read -r line; do
    local types_field
    types_field=$(echo "$line" | sed 's/.*types="\([^"]*\)".*/\1/' 2>/dev/null)
    if [ -n "$types_field" ] && [ "$types_field" != "$line" ]; then
      # Split on ", " and output each type
      echo "$types_field" | tr ',' '\n' | sed 's/^ *//'
    fi
  done < "$security_log" > "$types_tmp"

  if [ -s "$types_tmp" ]; then
    # Sort and count, then display bars
    local counts_tmp
    counts_tmp=$(mktemp)
    sort "$types_tmp" | uniq -c | sort -rn > "$counts_tmp"
    while IFS= read -r count_line; do
      local count type_name
      count=$(echo "$count_line" | awk '{print $1}')
      type_name=$(echo "$count_line" | awk '{$1=""; print}' | sed 's/^ *//')
      [ -n "$type_name" ] && bar "$type_name" "$count" "$total"
    done < "$counts_tmp"
    rm -f "$counts_tmp"
  fi
  rm -f "$types_tmp"
}

_stats_sessions() {
  step "Sessions"

  local backups_dir="$CLAUDE_DIR/backups"
  if [ ! -d "$backups_dir" ] || [ -z "$(ls -A "$backups_dir" 2>/dev/null)" ]; then
    info "No transcript backups found."
    return
  fi

  # Count files
  local file_count=0
  for f in "$backups_dir"/*; do
    [ -f "$f" ] && file_count=$(( file_count + 1 ))
  done
  kv "Backups" "$file_count transcripts"

  # Date range — use file modification times
  local oldest newest
  oldest=$(ls -t "$backups_dir"/* 2>/dev/null | tail -1)
  newest=$(ls -t "$backups_dir"/* 2>/dev/null | head -1)
  if [ -n "$oldest" ] && [ -n "$newest" ]; then
    local oldest_date newest_date
    if oldest_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$oldest" 2>/dev/null); then
      newest_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$newest" 2>/dev/null)
    elif oldest_date=$(stat -c "%y" "$oldest" 2>/dev/null | cut -d' ' -f1); then
      newest_date=$(stat -c "%y" "$newest" 2>/dev/null | cut -d' ' -f1)
    else
      oldest_date="unknown"
      newest_date="unknown"
    fi
    kv "Date range" "$oldest_date — $newest_date"
  fi

  # Disk usage
  local total_bytes=0
  for f in "$backups_dir"/*; do
    [ -f "$f" ] || continue
    local fsize
    if fsize=$(stat -f "%z" "$f" 2>/dev/null); then
      total_bytes=$(( total_bytes + fsize ))
    elif fsize=$(stat -c "%s" "$f" 2>/dev/null); then
      total_bytes=$(( total_bytes + fsize ))
    fi
  done
  local human_size
  human_size=$(format_bytes "$total_bytes")
  kv "Disk usage" "$human_size"
}

# ── Main ─────────────────────────────────────────────────────

cmd_stats() {
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/platform.sh"

  local section=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge stats${_C_RST} — Show installation statistics\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge stats              # all sections\n"
        printf "  forge stats --security   # security events only\n"
        printf "  forge stats --sessions   # session backups only\n"
        return 0
        ;;
      --security)
        section="security"
        shift
        ;;
      --sessions)
        section="sessions"
        shift
        ;;
      *)
        fail "Unknown option: $1"
        echo "Usage: forge stats [--security] [--sessions] [--help]"
        return 1
        ;;
    esac
  done

  if [ ! -f "$MANIFEST_FILE" ]; then
    fail "Forge is not installed (no manifest found)"
    info "Run: forge install"
    return 1
  fi

  banner "Stats"

  case "$section" in
    security) _stats_security ;;
    sessions) _stats_sessions ;;
    *)
      _stats_installation
      _stats_security
      _stats_sessions
      ;;
  esac
}
