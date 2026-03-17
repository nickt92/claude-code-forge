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
# Runs up to MAX_PARALLEL concurrent installations.
# Returns: sets PLUGINS_INSTALLED and PLUGINS_FAILED counts.
MAX_PARALLEL="${MAX_PARALLEL:-4}"

install_plugins() {
  local plugin_list="$1"
  PLUGINS_INSTALLED=0
  PLUGINS_FAILED=0

  local total
  total=$(echo "$plugin_list" | grep -c .)

  # Collect plugins into an array
  local -a plugins=()
  while IFS= read -r plugin; do
    [ -n "$plugin" ] || continue
    plugins+=("$plugin")
  done <<< "$plugin_list"

  progress_start "$total" "Installing plugins"

  local -a pids=()
  local -a pid_plugins=()
  local active=0
  local tmpdir
  tmpdir="$(mktemp -d)"

  for plugin in "${plugins[@]}"; do
    # Launch background install
    (
      if claude plugins add "$plugin" </dev/null 2>/dev/null; then
        touch "$tmpdir/ok-$(echo "$plugin" | tr '/' '_')"
      else
        touch "$tmpdir/fail-$(echo "$plugin" | tr '/' '_')"
      fi
    ) &
    pids+=($!)
    pid_plugins+=("$plugin")
    ((active++))

    # Cap concurrency
    if [ "$active" -ge "$MAX_PARALLEL" ]; then
      # Wait for any one to finish
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
      pid_plugins=("${pid_plugins[@]:1}")
      ((active--))
      progress_tick
    fi
  done

  # Wait for remaining
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
    progress_tick
  done

  # Count results
  PLUGINS_INSTALLED=$(find "$tmpdir" -name 'ok-*' 2>/dev/null | wc -l | tr -d ' ')
  PLUGINS_FAILED=$(find "$tmpdir" -name 'fail-*' 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$tmpdir"

  if [ "$PLUGINS_FAILED" -eq 0 ]; then
    progress_done "$PLUGINS_INSTALLED plugins installed"
  else
    progress_done "$PLUGINS_INSTALLED plugins installed ($PLUGINS_FAILED skipped)"
  fi
  # Reset terminal state — claude CLI (Node.js) may dirty the tty on failure
  # Skip on Windows (Git Bash) — /dev/tty may not exist
  [ -c /dev/tty ] && stty sane < /dev/tty 2>/dev/null || true
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
