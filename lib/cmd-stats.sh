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

# Rotate telemetry entries older than 30 days (shared by human + JSON output).
# Uses cp+mv to avoid data loss from concurrent hook appenders.
_rotate_telemetry() {
  local telemetry_log="$1"
  [ -f "$telemetry_log" ] || return
  local cutoff
  cutoff=$(( $(date +%s) - 2592000 ))
  local rotated_tmp
  rotated_tmp=$(mktemp "${telemetry_log}.rot.XXXXXX")
  awk -F'|' -v cutoff="$cutoff" '$1 >= cutoff' "$telemetry_log" > "$rotated_tmp"
  if [ "$(wc -l < "$rotated_tmp" | tr -d ' ')" -lt "$(wc -l < "$telemetry_log" | tr -d ' ')" ]; then
    mv "$rotated_tmp" "$telemetry_log"
  else
    rm -f "$rotated_tmp"
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

# ── Session Scorecard ─────────────────────────────────────────

_stats_session() {
  step "Session Scorecard"

  local session_log="${TMPDIR:-/tmp}/forge-session-log-${PPID}"
  if [ ! -f "$session_log" ] || [ ! -s "$session_log" ]; then
    info "No session events recorded yet."
    return
  fi

  local total
  total=$(wc -l < "$session_log" | tr -d ' ')
  kv "Total events" "$total"

  # Count by hook
  local hooks_tmp
  hooks_tmp=$(mktemp)
  cut -d'|' -f2 "$session_log" | sort | uniq -c | sort -rn > "$hooks_tmp"
  while IFS= read -r count_line; do
    local count hook_name
    count=$(echo "$count_line" | awk '{print $1}')
    hook_name=$(echo "$count_line" | awk '{print $2}')
    [ -n "$hook_name" ] && bar "$hook_name" "$count" "$total"
  done < "$hooks_tmp"
  rm -f "$hooks_tmp"

  # Count by outcome
  local blocks allows
  blocks=$(grep -c '|block$' "$session_log" 2>/dev/null || echo 0)
  allows=$(grep -c '|allow$' "$session_log" 2>/dev/null || echo 0)
  local detects overrides
  detects=$(grep -c '|detect$' "$session_log" 2>/dev/null || echo 0)
  overrides=$(grep -c '|override$' "$session_log" 2>/dev/null || echo 0)

  echo ""
  kv "Allowed" "$allows"
  [ "$blocks" -gt 0 ] && kv "Blocked" "$blocks"
  [ "$detects" -gt 0 ] && kv "Detected" "$detects"
  [ "$overrides" -gt 0 ] && kv "Overrides" "$overrides"
}

# ── Hook Telemetry ───────────────────────────────────────────

_stats_hooks() {
  step "Hook Telemetry"

  local telemetry_log="$CLAUDE_DIR/hook-telemetry.log"
  if [ ! -f "$telemetry_log" ] || [ ! -s "$telemetry_log" ]; then
    info "No hook telemetry recorded yet."
    return
  fi

  _rotate_telemetry "$telemetry_log"

  local total
  total=$(wc -l < "$telemetry_log" | tr -d ' ')
  kv "Total invocations" "$total (last 30 days)"

  # Count by hook
  local hooks_tmp
  hooks_tmp=$(mktemp)
  cut -d'|' -f2 "$telemetry_log" | sort | uniq -c | sort -rn > "$hooks_tmp"
  while IFS= read -r count_line; do
    local count hook_name
    count=$(echo "$count_line" | awk '{print $1}')
    hook_name=$(echo "$count_line" | awk '{print $2}')
    [ -n "$hook_name" ] && bar "$hook_name" "$count" "$total"
  done < "$hooks_tmp"
  rm -f "$hooks_tmp"

  # Block rate
  local blocks
  blocks=$(grep -c '|block$' "$telemetry_log" 2>/dev/null || echo 0)
  if [ "$total" -gt 0 ]; then
    local block_rate=$(( blocks * 100 / total ))
    kv "Block rate" "${block_rate}% ($blocks/$total)"
  fi

  # Average duration
  local total_dur=0 dur_count=0
  read -r total_dur dur_count < <(awk -F'|' '$3 > 0 { s+=$3; c++ } END { print s+0, c+0 }' "$telemetry_log")
  if [ "$dur_count" -gt 0 ]; then
    local avg_dur=$(( total_dur / dur_count ))
    kv "Avg duration" "${avg_dur}ms"
  fi
}

# ── JSON Output ─────────────────────────────────────────────

_stats_hooks_json() {
  local telemetry_log="$CLAUDE_DIR/hook-telemetry.log"
  if [ ! -f "$telemetry_log" ] || [ ! -s "$telemetry_log" ]; then
    printf '{"total_invocations":0,"by_hook":{},"block_rate":0,"avg_duration_ms":0}\n'
    return
  fi

  _rotate_telemetry "$telemetry_log"

  awk -F'|' '
  {
    total++
    hooks[$2]++
    if ($4 == "block") blocks++
    if ($3 > 0) { dur_sum += $3; dur_count++ }
  }
  END {
    block_rate = (total > 0) ? int(blocks * 100 / total) : 0
    avg_dur = (dur_count > 0) ? int(dur_sum / dur_count) : 0
    printf "{\"total_invocations\":%d,\"by_hook\":{", total
    first = 1
    for (h in hooks) {
      if (!first) printf ","
      printf "\"%s\":%d", h, hooks[h]
      first = 0
    }
    printf "},\"block_rate\":%d,\"avg_duration_ms\":%d}\n", block_rate, avg_dur
  }' "$telemetry_log"
}

_stats_session_json() {
  local session_log="${TMPDIR:-/tmp}/forge-session-log-${PPID}"
  if [ ! -f "$session_log" ] || [ ! -s "$session_log" ]; then
    printf '{"total_events":0,"by_hook":{},"blocks":0,"allows":0,"detects":0,"overrides":0}\n'
    return
  fi

  awk -F'|' '
  {
    total++
    hooks[$2]++
    if ($4 == "block") blocks++
    if ($4 == "allow") allows++
    if ($4 == "detect") detects++
    if ($4 == "override") overrides++
  }
  END {
    printf "{\"total_events\":%d,\"by_hook\":{", total
    first = 1
    for (h in hooks) {
      if (!first) printf ","
      printf "\"%s\":%d", h, hooks[h]
      first = 0
    }
    printf "},\"blocks\":%d,\"allows\":%d,\"detects\":%d,\"overrides\":%d}\n", blocks, allows, detects, overrides
  }' "$session_log"
}

# ── Main ─────────────────────────────────────────────────────

cmd_stats() {
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/platform.sh"

  local section=""
  local json_mode=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge stats${_C_RST} — Show installation statistics\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge stats              # all sections\n"
        printf "  forge stats --security   # security events only\n"
        printf "  forge stats --sessions   # session backups only\n"
        printf "  forge stats --session    # current session scorecard\n"
        printf "  forge stats --hooks      # hook telemetry (30 days)\n"
        printf "  forge stats --json       # all sections as JSON\n"
        printf "  forge stats --hooks --json  # single section as JSON\n"
        return 0
        ;;
      --json)
        json_mode=true
        shift
        ;;
      --security)
        section="security"
        shift
        ;;
      --sessions)
        section="sessions"
        shift
        ;;
      --session)
        section="session"
        shift
        ;;
      --hooks)
        section="hooks"
        shift
        ;;
      *)
        fail "Unknown option: $1"
        echo "Usage: forge stats [--security] [--sessions] [--session] [--hooks] [--json] [--help]"
        return 1
        ;;
    esac
  done

  if [ ! -f "$MANIFEST_FILE" ]; then
    fail "Forge is not installed (no manifest found)"
    info "Run: forge install"
    return 1
  fi

  if [ "$json_mode" = true ]; then
    case "$section" in
      hooks)    _stats_hooks_json ;;
      session)  _stats_session_json ;;
      *)
        local hooks_json session_json
        hooks_json=$(_stats_hooks_json)
        session_json=$(_stats_session_json)
        printf '{"hooks":%s,"session":%s}\n' "$hooks_json" "$session_json"
        ;;
    esac
    return 0
  fi

  banner "Stats"

  case "$section" in
    security) _stats_security ;;
    sessions) _stats_sessions ;;
    session)  _stats_session ;;
    hooks)    _stats_hooks ;;
    *)
      _stats_installation
      _stats_security
      _stats_sessions
      _stats_session
      _stats_hooks
      ;;
  esac
}
