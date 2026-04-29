#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-permissions — manage Claude Code permission presets
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Apply curated permission presets to ~/.claude/settings.json
# that control what Claude Code can do without asking.
#
# Usage:
#   forge permissions                      Show current preset + effective permissions
#   forge permissions --list               List available presets with descriptions
#   forge permissions --preset <name>      Apply a preset
#   forge permissions --json               Machine-readable output
#   forge permissions --list --json        List presets as JSON

cmd_permissions() {
  source "$FORGE_SOURCE_DIR/lib/permissions-merge.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  local json_mode=false
  local list_mode=false
  local preset_name=""

  # Parse flags
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --list) list_mode=true; shift ;;
      --preset)
        shift
        preset_name="${1:-}"
        [ -z "$preset_name" ] && { fail "Missing preset name after --preset"; return 1; }
        shift
        ;;
      --help|-h) _permissions_help; return 0 ;;
      *) args+=("$1"); shift ;;
    esac
  done

  # Route to the right action
  if [ -n "$preset_name" ]; then
    _permissions_apply "$preset_name"
  elif $list_mode; then
    _permissions_list
  else
    _permissions_show
  fi
}

# ── List presets ─────────────────────────────────────────────

_permissions_list() {
  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"

  if $json_mode; then
    jq '
      [.presets | to_entries[] | {
        id: .key,
        label: .value.label,
        tier: .value.tier,
        description: .value.description,
        detail: .value.detail,
        permissions: .value.permissions,
        inherits: .value.inherits
      }] | sort_by(.tier)
    ' "$PRESETS_FILE"
  else
    printf "\n${_C_BOLD}forge permissions${_C_RST} — Claude Code permission presets\n"
    printf "\n${_C_BOLD}Available presets:${_C_RST}\n\n"

    # Read presets and display
    local ids
    ids=$(jq -r '.presets | to_entries | sort_by(.value.tier)[] | .key' "$PRESETS_FILE")

    while IFS= read -r id; do
      local label tier desc detail recommended=""
      label=$(jq -r --arg id "$id" '.presets[$id].label' "$PRESETS_FILE")
      tier=$(jq -r --arg id "$id" '.presets[$id].tier' "$PRESETS_FILE")
      desc=$(jq -r --arg id "$id" '.presets[$id].description' "$PRESETS_FILE")
      detail=$(jq -r --arg id "$id" '.presets[$id].detail' "$PRESETS_FILE")

      [ "$id" = "full-autonomy" ] && recommended=" ${_C_GREEN}(recommended)${_C_RST}"

      printf "  ${_C_BOLD}%s${_C_RST}%s\n" "$label" "$recommended"
      printf "  ${_C_DIM}Tier %s — %s${_C_RST}\n" "$tier" "$id"
      printf "  %s\n" "$desc"
      printf "  ${_C_DIM}%s${_C_RST}\n\n" "$detail"
    done <<< "$ids"

    printf "${_C_DIM}Apply with: forge permissions --preset <name>${_C_RST}\n"
  fi
}

# ── Show current state ───────────────────────────────────────

_permissions_show() {
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  local current_preset="none"
  local current_permissions='[]'

  # Get preset from manifest
  if [ -f "$MANIFEST_FILE" ]; then
    current_preset=$(jq -r '.installed.permissions_preset // "none"' "$MANIFEST_FILE" 2>/dev/null)
  fi

  # Get effective permissions from settings
  if [ -f "$SETTINGS_FILE" ]; then
    current_permissions=$(jq '.permissions.allow // []' "$SETTINGS_FILE" 2>/dev/null)
  fi

  if $json_mode; then
    jq -n \
      --arg preset "$current_preset" \
      --argjson permissions "$current_permissions" \
      '{currentPreset: $preset, effectivePermissions: $permissions}'
  else
    printf "\n${_C_BOLD}Permission Status${_C_RST}\n\n"

    if [ "$current_preset" = "none" ]; then
      printf "  Preset: ${_C_DIM}none (Claude asks for everything)${_C_RST}\n"
    else
      local label
      label=$(jq -r --arg id "$current_preset" '.presets[$id].label // $id' \
        "$FORGE_SOURCE_DIR/templates/permission-presets.json" 2>/dev/null)
      printf "  Preset: ${_C_BOLD}%s${_C_RST} (%s)\n" "$label" "$current_preset"
    fi

    local count
    count=$(echo "$current_permissions" | jq 'length')
    printf "  Auto-approved rules: ${_C_BOLD}%s${_C_RST}\n" "$count"

    if [ "$count" -gt 0 ]; then
      printf "\n  ${_C_DIM}Effective permissions:${_C_RST}\n"
      echo "$current_permissions" | jq -r '.[]' | while IFS= read -r rule; do
        printf "    ${_C_GREEN}+${_C_RST} %s\n" "$rule"
      done
    fi

    printf "\n${_C_DIM}Change with: forge permissions --preset <name>${_C_RST}\n"
    printf "${_C_DIM}List presets: forge permissions --list${_C_RST}\n"
  fi
}

# ── Apply preset ─────────────────────────────────────────────

_permissions_apply() {
  local preset_name="$1"
  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  # Validate preset exists
  local valid
  valid=$(jq -r --arg name "$preset_name" '.presets[$name] // empty' "$PRESETS_FILE")
  if [ -z "$valid" ]; then
    fail "Unknown preset: $preset_name"
    printf "\n${_C_DIM}Available presets:${_C_RST}\n"
    jq -r '.presets | keys[]' "$PRESETS_FILE" | while IFS= read -r id; do
      printf "  %s\n" "$id"
    done
    return 1
  fi

  # Resolve full permission list for the new preset
  local resolved
  resolved=$(resolve_preset_permissions "$preset_name" "$PRESETS_FILE")

  # If manifest has a previous preset, unmerge old permissions first
  if [ -f "$MANIFEST_FILE" ]; then
    local old_preset old_added
    old_preset=$(jq -r '.installed.permissions_preset // "none"' "$MANIFEST_FILE" 2>/dev/null)
    old_added=$(jq '.installed.permissions_added // []' "$MANIFEST_FILE" 2>/dev/null)

    if [ "$old_preset" != "none" ] && [ "$old_added" != "[]" ]; then
      unmerge_permissions "$SETTINGS_FILE" "$old_added"
    fi
  fi

  # Merge new permissions
  merge_permissions "$SETTINGS_FILE" "$preset_name" "$PRESETS_FILE"

  # Update manifest
  _permissions_update_manifest "$preset_name" "$resolved"

  local label count
  label=$(jq -r --arg id "$preset_name" '.presets[$id].label' "$PRESETS_FILE")
  count=$(echo "$resolved" | jq 'length')

  if $json_mode; then
    jq -n \
      --arg preset "$preset_name" \
      --arg label "$label" \
      --argjson count "$count" \
      --argjson permissions "$resolved" \
      '{applied: true, preset: $preset, label: $label, count: $count, permissions: $permissions}'
  else
    ok "Applied ${_C_BOLD}${label}${_C_RST} preset. ${count} permissions auto-approved."
  fi
}

# ── Manifest update ──────────────────────────────────────────

_permissions_update_manifest() {
  local preset_name="$1"
  local resolved_json="$2"

  if [ ! -f "$MANIFEST_FILE" ]; then
    return 0
  fi

  local tmp_manifest="${MANIFEST_FILE}.tmp"
  jq --arg preset "$preset_name" --argjson added "$resolved_json" '
    .installed.permissions_preset = $preset |
    .installed.permissions_added = $added
  ' "$MANIFEST_FILE" > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST_FILE"
}

# ── Help ─────────────────────────────────────────────────────

_permissions_help() {
  printf "\n${_C_BOLD}forge permissions${_C_RST} — manage Claude Code permission presets\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge permissions                      Show current preset\n"
  printf "  forge permissions --list               List available presets\n"
  printf "  forge permissions --preset <name>      Apply a preset\n"
  printf "  forge permissions --json               Machine-readable output\n"
  printf "  forge permissions --list --json        List presets as JSON\n"
  printf "\n${_C_BOLD}Presets:${_C_RST}\n"
  printf "  ${_C_BOLD}ask-before-changes${_C_RST}   Read-only auto-approved\n"
  printf "  ${_C_BOLD}auto-edit${_C_RST}            Read + write auto-approved\n"
  printf "  ${_C_BOLD}full-autonomy${_C_RST}        Dev commands auto-approved (recommended)\n"
}
