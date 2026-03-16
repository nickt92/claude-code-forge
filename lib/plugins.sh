#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Plugins — plugin group resolution and installation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/plugins.sh
#
# Public API:
#   resolve_plugin_list   — returns newline-separated plugin list for a group
#   install_plugins       — installs plugins from a newline-separated list
#   get_plugin_group_names — returns available group names
#   get_default_plugin_group — returns default group from a profile

FORGE_SOURCE_DIR="${FORGE_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLUGIN_GROUPS_FILE="$FORGE_SOURCE_DIR/templates/plugin-groups.json"

# Resolve a plugin group name to a newline-separated list of plugin identifiers.
# Falls back to "full" if group not found.
resolve_plugin_list() {
  local group="${1:-full}"

  if [ ! -f "$PLUGIN_GROUPS_FILE" ]; then
    fail "Plugin groups file not found: $PLUGIN_GROUPS_FILE"
    return 1
  fi

  local plugins
  plugins=$(jq -r --arg g "$group" '.[$g] // empty | .[]' "$PLUGIN_GROUPS_FILE" 2>/dev/null)

  if [ -z "$plugins" ]; then
    warn "Unknown plugin group '$group' — falling back to 'full'"
    plugins=$(jq -r '.full[]' "$PLUGIN_GROUPS_FILE" 2>/dev/null)
  fi

  echo "$plugins"
}

# Install plugins from a newline-separated list.
# Returns: sets PLUGINS_INSTALLED and PLUGINS_FAILED counts.
install_plugins() {
  local plugin_list="$1"
  PLUGINS_INSTALLED=0
  PLUGINS_FAILED=0

  local total
  total=$(echo "$plugin_list" | grep -c .)

  progress_start "$total" "Installing plugins"
  while IFS= read -r plugin; do
    [ -n "$plugin" ] || continue
    if claude plugins add "$plugin" </dev/null 2>/dev/null; then
      ((PLUGINS_INSTALLED++))
    else
      ((PLUGINS_FAILED++))
    fi
    progress_tick
  done <<< "$plugin_list"

  if [ "$PLUGINS_FAILED" -eq 0 ]; then
    progress_done "$PLUGINS_INSTALLED plugins installed"
  else
    progress_done "$PLUGINS_INSTALLED plugins installed ($PLUGINS_FAILED skipped)"
  fi
  # Reset terminal state — claude CLI (Node.js) may dirty the tty on failure
  stty sane < /dev/tty 2>/dev/null || true
}

# Return available plugin group names (newline-separated).
get_plugin_group_names() {
  jq -r 'keys[]' "$PLUGIN_GROUPS_FILE" 2>/dev/null
}

# Get default plugin group from a profile JSON file.
# Returns "full" if not specified.
get_default_plugin_group() {
  local profile_file="$1"
  local group
  group=$(jq -r '.default_plugin_group // "full"' "$profile_file" 2>/dev/null)
  echo "$group"
}
