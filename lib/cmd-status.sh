#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-status — show current forge installation status
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Read-only command that displays persona, plugins, version,
# hooks, install timestamp, and source directory.
#
# Usage:
#   forge status

cmd_status() {
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"

  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    printf "\n${_C_BOLD}forge status${_C_RST} — Show current installation status\n"
    printf "\n${_C_BOLD}Usage:${_C_RST}\n"
    printf "  forge status\n"
    printf "\nDisplays persona, plugin group, version, hooks, and install info.\n"
    return 0
  fi

  if [ ! -f "$MANIFEST_FILE" ]; then
    fail "Forge is not installed (no manifest found)"
    info "Run: forge install"
    return 1
  fi

  banner "Status"

  # Persona
  local persona="unknown" label="unknown"
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    persona=$(jq -r '.persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
    label=$(jq -r '.label // .persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
  fi
  kv "Persona" "$label ($persona)"

  # Plugin group
  local plugin_group
  plugin_group=$(jq -r '.plugin_group // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  local plugin_count
  plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  kv "Plugins" "$plugin_group ($plugin_count plugins)"

  # Version
  local installed_version
  installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  if [ "$installed_version" = "$FORGE_VERSION" ]; then
    kv "Version" "$FORGE_VERSION"
  else
    kv "Version" "$installed_version (source: $FORGE_VERSION)"
  fi

  # Hooks
  local hook_count=0
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
      ((hook_count++))
    fi
  done < <(forge_shipped_hooks)
  kv "Hooks" "$hook_count installed"

  # Install timestamp
  local timestamp
  timestamp=$(jq -r '.install_timestamp // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  kv "Installed" "$timestamp"

  # Source directory
  local source_dir
  source_dir=$(jq -r '.source_dir // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  kv "Source" "$source_dir"
}
