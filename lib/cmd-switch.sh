#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-switch — switch to a different persona
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Reassembles CLAUDE.md from the new profile without reinstalling
# everything. Updates manifest persona field.
#
# Usage:
#   forge switch <persona>
#   forge switch senior-engineer
#   forge switch custom-my-team

cmd_switch() {
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  local USER_PROFILES_DIR="$CLAUDE_DIR/profiles"
  local json_mode=false
  local list_mode=false
  local persona=""

  # Parse flags
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --list) list_mode=true; shift ;;
      --help|-h) list_mode=true; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  set -- "${args[@]}"

  persona="${1:-}"

  # --list mode (or no args without --json)
  if $list_mode || { [ -z "$persona" ] && ! $json_mode; }; then
    if $json_mode; then
      _switch_list_json "$USER_PROFILES_DIR"
    else
      _switch_list_human "$USER_PROFILES_DIR"
    fi
    return 0
  fi

  # No persona and --json but no --list → error
  if [ -z "$persona" ]; then
    if $json_mode; then
      echo '{"error": "No persona specified"}' >&2
      return 1
    fi
    _switch_list_human "$USER_PROFILES_DIR"
    return 0
  fi

  # Switch to persona
  local profile_file="$PROFILES_DIR/${persona}.json"

  # Check user-space profiles as fallback
  if [ ! -f "$profile_file" ] && [ -f "$USER_PROFILES_DIR/${persona}.json" ]; then
    profile_file="$USER_PROFILES_DIR/${persona}.json"
  fi

  if [ ! -f "$profile_file" ]; then
    if $json_mode; then
      printf '{"error": "Unknown persona: %s"}\n' "$persona" >&2
      return 1
    fi
    fail "Unknown persona: $persona"
    echo ""
    printf "${_C_BOLD}Available personas:${_C_RST}\n"
    for f in "$PROFILES_DIR"/*.json; do
      [ -f "$f" ] || continue
      printf "  %s\n" "$(jq -r '.persona' "$f")"
    done
    if [ -d "$USER_PROFILES_DIR" ]; then
      for f in "$USER_PROFILES_DIR"/*.json; do
        [ -f "$f" ] || continue
        printf "  %s\n" "$(jq -r '.persona' "$f")"
      done
    fi
    return 1
  fi

  # Assemble new CLAUDE.md
  assemble_claude_md "$profile_file" "$CLAUDE_DIR/CLAUDE.md"

  # Copy new profile
  cp "$profile_file" "$CLAUDE_DIR/profile.json"

  # Update manifest persona field
  if [ -f "$MANIFEST_FILE" ]; then
    local tmp_manifest="${MANIFEST_FILE}.tmp"
    jq --arg p "$persona" '.persona = $p' "$MANIFEST_FILE" > "$tmp_manifest"
    mv "$tmp_manifest" "$MANIFEST_FILE"
  fi

  local lines label
  lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
  label=$(jq -r '.label' "$profile_file")

  if $json_mode; then
    jq -n \
      --arg persona "$persona" \
      --arg label "$label" \
      --argjson lines "$lines" \
      '{"switched": true, "persona": $persona, "label": $label, "lines": $lines}'
  else
    ok "Switched to ${_C_BOLD}${label}${_C_RST} (${lines} lines)"
  fi
}

# Helper: list personas as JSON array
_switch_list_json() {
  local user_profiles_dir="$1"
  local first=true
  printf '['

  for f in "$PROFILES_DIR"/*.json; do
    [ -f "$f" ] || continue
    if $first; then first=false; else printf ','; fi
    jq '{persona, label, description, axes, quality, default_plugin_group, source: "builtin"}' "$f"
  done

  if [ -d "$user_profiles_dir" ]; then
    for f in "$user_profiles_dir"/*.json; do
      [ -f "$f" ] || continue
      if $first; then first=false; else printf ','; fi
      jq '{persona, label, description, axes, quality, default_plugin_group, source: "custom"}' "$f"
    done
  fi

  printf ']\n'
}

# Helper: list personas in human-readable format
_switch_list_human() {
  local user_profiles_dir="$1"
  printf "\n${_C_BOLD}forge switch${_C_RST} — Switch to a different persona\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge switch ${_C_BOLD}<persona>${_C_RST}\n"
  printf "\n${_C_BOLD}Available personas:${_C_RST}\n"
  for f in "$PROFILES_DIR"/*.json; do
    [ -f "$f" ] || continue
    local key label
    key=$(jq -r '.persona' "$f")
    label=$(jq -r '.label' "$f")
    printf "  ${_C_BOLD}%-25s${_C_RST} ${_C_DIM}%s${_C_RST}\n" "$key" "$label"
  done
  if [ -d "$user_profiles_dir" ]; then
    for f in "$user_profiles_dir"/*.json; do
      [ -f "$f" ] || continue
      local key label
      key=$(jq -r '.persona' "$f")
      label=$(jq -r '.label' "$f")
      printf "  ${_C_BOLD}%-25s${_C_RST} ${_C_DIM}%s${_C_RST}\n" "$key" "$label"
    done
  fi
}
