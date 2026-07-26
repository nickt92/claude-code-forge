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

  local json_output=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json_output=true
        ;;
      --help|-h)
        printf "\n${_C_BOLD}forge status${_C_RST} — Show current installation status\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge status          Human-readable status\n"
        printf "  forge status --json   Structured JSON output\n"
        printf "\nDisplays persona, plugin group, version, hooks, and install info.\n"
        return 0
        ;;
      *)
        forge_fail "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  if [ ! -f "$MANIFEST_FILE" ]; then
    if [ "$json_output" = true ]; then
      jq -n '{schema_version: 1, error: "Forge is not installed (no manifest found)"}'
    else
      forge_fail "Forge is not installed (no manifest found)"
      info "Run: forge install"
    fi
    return 1
  fi

  # Persona
  local persona="unknown" label="unknown"
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    persona=$(jq -r '.persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
    label=$(jq -r '.label // .persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
  fi

  # Plugin group
  local plugin_group
  plugin_group=$(jq -r '.plugin_group // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  local plugin_count
  plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)

  # Version
  local installed_version
  installed_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)

  # Hooks
  local hook_count=0
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
      ((hook_count++))
    fi
  done < <(forge_shipped_hooks)

  # Install timestamp
  local timestamp
  timestamp=$(jq -r '.install_timestamp // "unknown"' "$MANIFEST_FILE" 2>/dev/null)

  # Source directory
  local source_dir
  source_dir=$(jq -r '.source_dir // "unknown"' "$MANIFEST_FILE" 2>/dev/null)

  if [ "$json_output" = true ]; then
    jq -n \
      --arg persona_id "$persona" \
      --arg persona_label "$label" \
      --arg plugin_group "$plugin_group" \
      --argjson plugin_count "$plugin_count" \
      --arg installed_version "$installed_version" \
      --arg source_version "$FORGE_VERSION" \
      --argjson hook_count "$hook_count" \
      --arg installed_at "$timestamp" \
      --arg source_dir "$source_dir" \
      '{
        schema_version: 1,
        persona: {id: $persona_id, label: $persona_label},
        plugins: {group: $plugin_group, count: $plugin_count},
        version: {installed: $installed_version, source: $source_version},
        hooks: {count: $hook_count},
        installed_at: $installed_at,
        source_dir: $source_dir
      }'
    return 0
  fi

  banner "Status"
  kv "Persona" "$label ($persona)"
  kv "Plugins" "$plugin_group ($plugin_count plugins)"
  if [ "$installed_version" = "$FORGE_VERSION" ]; then
    kv "Version" "$FORGE_VERSION"
  else
    kv "Version" "$installed_version (source: $FORGE_VERSION)"
  fi
  kv "Hooks" "$hook_count installed"
  kv "Installed" "$timestamp"
  kv "Source" "$source_dir"
}
