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
MARKETPLACES_FILE="$FORGE_SOURCE_DIR/templates/marketplaces.json"

# Extract the marketplace name from a "name@marketplace" plugin identifier.
# Returns the whole string if no '@' is present (caller treats as unmapped).
_plugin_marketplace() {
  printf '%s' "${1##*@}"
}

# Resolve a marketplace name to its add-source (e.g. "wshobson/agents").
# Empty output means the name is not mapped in marketplaces.json.
_marketplace_source() {
  local name="$1"
  [ -f "$MARKETPLACES_FILE" ] || return 0
  jq -r --arg n "$name" '.[$n] // empty' "$MARKETPLACES_FILE" 2>/dev/null
}

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

# Install plugins from a newline-separated list of "name@marketplace" ids.
#
# Current Claude Code requires a two-step flow: register the marketplace
# (`claude plugin marketplace add <source>`), then install the plugin
# (`claude plugin install <name>@<marketplace> --scope user`). Marketplace
# registration runs sequentially and completes BEFORE the parallel install
# fan-out, so installs never race an unregistered marketplace.
#
# Failures are surfaced with their real reason — never silently skipped.
# A marketplace that cannot be registered fails its dependent plugins
# (with that reason) but does not abort the rest of the install.
#
# Runs up to MAX_PARALLEL concurrent installs.
# Returns: sets PLUGINS_INSTALLED and PLUGINS_FAILED counts.
MAX_PARALLEL="${MAX_PARALLEL:-4}"

install_plugins() {
  local plugin_list="$1"
  PLUGINS_INSTALLED=0
  PLUGINS_FAILED=0

  # Collect plugins into an array
  local -a plugins=()
  local plugin
  while IFS= read -r plugin; do
    [ -n "$plugin" ] || continue
    plugins+=("$plugin")
  done <<< "$plugin_list"

  local total=${#plugins[@]}
  [ "$total" -eq 0 ] && return 0

  progress_start "$total" "Installing plugins"

  local tmpdir
  tmpdir="$(mktemp -d)"

  # ── Phase 1: register required marketplaces (sequential, before fan-out) ──
  # mkt_failed accumulates "marketplace<TAB>reason" lines; dependent plugins
  # are failed without an install attempt.
  local mkt_failed=""
  local existing_marketplaces mkt source err
  existing_marketplaces="$(claude plugin marketplace list 2>/dev/null || true)"

  while IFS= read -r mkt; do
    [ -n "$mkt" ] || continue
    # Already registered? Idempotent success. Match the "❯ <name>" line shape
    # rather than a bare substring, which could collide with a Source URL.
    if printf '%s\n' "$existing_marketplaces" | grep -qE "❯[[:space:]]+${mkt}([[:space:]]|\$)"; then
      continue
    fi
    source="$(_marketplace_source "$mkt")"
    if [ -z "$source" ]; then
      mkt_failed+="${mkt}"$'\t'"no source mapping in marketplaces.json"$'\n'
      continue
    fi
    # Flatten multiline CLI errors so the awk field-2 lookup stays single-line.
    if ! err="$(claude plugin marketplace add "$source" </dev/null 2>&1)"; then
      mkt_failed+="${mkt}"$'\t'"marketplace add failed: $(printf '%s' "$err" | tr '\n' ' ')"$'\n'
    fi
  done <<< "$(printf '%s\n' "${plugins[@]}" | sed 's/.*@//' | sort -u)"

  # ── Phase 2: install plugins (parallel) ──
  local -a pids=()
  local active=0 idx=0 reason
  for plugin in "${plugins[@]}"; do
    idx=$((idx + 1))
    mkt="$(_plugin_marketplace "$plugin")"

    # If the plugin's marketplace could not be registered, fail it now.
    reason=""
    if [ -n "$mkt_failed" ]; then
      reason="$(printf '%s' "$mkt_failed" | awk -F'\t' -v m="$mkt" '$1==m {print $2; exit}')"
    fi
    if [ -n "$reason" ]; then
      printf '%s\t%s\n' "$plugin" "$reason" > "$tmpdir/fail-$idx"
      progress_tick
      continue
    fi

    (
      if e="$(claude plugin install "$plugin" --scope user </dev/null 2>&1)"; then
        : > "$tmpdir/ok-$idx"
      else
        # Flatten multiline CLI errors so the failure stays on one line.
        printf '%s\t%s\n' "$plugin" "$(printf '%s' "${e:-install failed}" | tr '\n' ' ')" > "$tmpdir/fail-$idx"
      fi
    ) &
    pids+=($!)
    active=$((active + 1))

    # Cap concurrency
    if [ "$active" -ge "$MAX_PARALLEL" ]; then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
      active=$((active - 1))
      progress_tick
    fi
  done

  # Wait for remaining
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
    progress_tick
  done

  # Count results
  PLUGINS_INSTALLED=$(find "$tmpdir" -name 'ok-*' 2>/dev/null | wc -l | tr -d ' ')
  PLUGINS_FAILED=$(find "$tmpdir" -name 'fail-*' 2>/dev/null | wc -l | tr -d ' ')

  if [ "$PLUGINS_FAILED" -eq 0 ]; then
    progress_done "$PLUGINS_INSTALLED plugins installed"
  else
    progress_done "$PLUGINS_INSTALLED plugins installed ($PLUGINS_FAILED failed)"
    # Surface the real reason for each failure — never a silent skip.
    local f fp fr
    for f in "$tmpdir"/fail-*; do
      [ -f "$f" ] || continue
      fp="$(cut -f1 "$f")"
      fr="$(cut -f2- "$f" | head -1)"
      warn "  ✗ ${fp}: ${fr}"
    done
  fi

  rm -rf "$tmpdir"
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
