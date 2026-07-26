#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-config — get/set persistent forge configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Manages forge-specific settings in ~/.claude/forge-config.json.
# Supports dotted key paths (e.g., dashboard.scan_path).
#
# Usage:
#   forge config get <key>              # read a value
#   forge config set <key> <value>      # write a value
#   forge config list                   # show all settings
#   forge config --help

FORGE_CONFIG_FILE="${CLAUDE_DIR}/forge-config.json"

# ── Helpers ──────────────────────────────────────────────────

# Ensure config file exists with valid JSON
_config_ensure_file() {
  if [ ! -f "$FORGE_CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$FORGE_CONFIG_FILE")"
    echo '{}' > "$FORGE_CONFIG_FILE"
  fi
}

# Convert dotted key to jq path (e.g., "dashboard.scan_path" → ".dashboard.scan_path")
# Validates key contains only safe characters to prevent jq injection.
_config_jq_path() {
  local key="$1"
  if [[ ! "$key" =~ ^[a-zA-Z0-9_.]+$ ]]; then
    forge_fail "Invalid key (alphanumeric, dots, underscores only): $key" >&2
    return 1
  fi
  echo ".${key}"
}

# ── Subcommands ──────────────────────────────────────────────

_config_get() {
  local key="$1"
  if [ -z "$key" ]; then
    forge_fail "Usage: forge config get <key>" >&2
    return 1
  fi

  _config_ensure_file

  local jq_path
  jq_path="$(_config_jq_path "$key")"
  local value
  value=$(jq -r "$jq_path // empty" "$FORGE_CONFIG_FILE" 2>/dev/null)

  if [ -z "$value" ]; then
    forge_fail "Key not set: $key" >&2
    return 1
  fi

  echo "$value"
}

_config_set() {
  local key="$1"
  local value="$2"

  if [ -z "$key" ] || [ -z "$value" ]; then
    forge_fail "Usage: forge config set <key> <value>" >&2
    return 1
  fi

  _config_ensure_file

  # Build the nested object from dotted key path
  # Split key on dots and build nested jq set expression
  local jq_path
  jq_path="$(_config_jq_path "$key")" || return 1

  # Determine if value is numeric
  local jq_expr
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    jq_expr="$jq_path = $value"
  else
    # Passed through the environment rather than --arg. On Git Bash, MSYS
    # rewrites any argv entry that looks like an absolute POSIX path before the
    # native jq binary sees it, so `forge config set dashboard.scan_path
    # /home/user/repos` stored "C:/Program Files/Git/home/user/repos".
    # Environment variables are not converted. jq's own file arguments still go
    # through argv, where the conversion is needed and correct.
    jq_expr="$jq_path = env.FORGE_CONFIG_VALUE"
  fi

  local tmp="${FORGE_CONFIG_FILE}.tmp"
  local rc=0
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    jq "$jq_expr" "$FORGE_CONFIG_FILE" > "$tmp" 2>/dev/null || rc=$?
  else
    FORGE_CONFIG_VALUE="$value" jq "$jq_expr" "$FORGE_CONFIG_FILE" > "$tmp" 2>/dev/null || rc=$?
  fi

  if [ "$rc" -eq 0 ] && [ -s "$tmp" ]; then
    mv "$tmp" "$FORGE_CONFIG_FILE"
    ok "$key = $value"
  else
    rm -f "$tmp"
    forge_fail "Failed to set $key" >&2
    return 1
  fi
}

_config_list() {
  _config_ensure_file

  if [ "$(cat "$FORGE_CONFIG_FILE")" = "{}" ]; then
    info "No configuration set. Use 'forge config set <key> <value>' to configure."
    return 0
  fi

  jq -r '
    paths(scalars) as $p |
    ($p | join(".")) + " = " + (getpath($p) | tostring)
  ' "$FORGE_CONFIG_FILE"
}

_config_help() {
  printf "\n${_C_BOLD}forge config${_C_RST} — manage forge settings\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge config get <key>           Read a config value\n"
  printf "  forge config set <key> <value>   Write a config value\n"
  printf "  forge config list                Show all settings\n"
  printf "\n${_C_BOLD}Keys:${_C_RST}\n"
  printf "  dashboard.scan_path    Directory to scan for repos (required for dashboard)\n"
  printf "  dashboard.scan_depth   Max directory depth to search (default: 3)\n"
  printf "\n${_C_BOLD}Examples:${_C_RST}\n"
  printf "  forge config set dashboard.scan_path ~/repos\n"
  printf "  forge config get dashboard.scan_path\n"
  printf "  forge config list\n"
}

# ── Entry Point ──────────────────────────────────────────────

cmd_config() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    get)   _config_get "$@" ;;
    set)   _config_set "$@" ;;
    list)  _config_list ;;
    --help|-h|help|"")
      _config_help
      ;;
    *)
      forge_fail "Unknown config subcommand: $subcmd"
      _config_help
      return 1
      ;;
  esac
}
