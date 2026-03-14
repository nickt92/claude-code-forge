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

  if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
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
    return 0
  fi

  local persona="$1"
  local profile_file="$PROFILES_DIR/${persona}.json"

  if [ ! -f "$profile_file" ]; then
    fail "Unknown persona: $persona"
    echo ""
    printf "${_C_BOLD}Available personas:${_C_RST}\n"
    for f in "$PROFILES_DIR"/*.json; do
      [ -f "$f" ] || continue
      printf "  %s\n" "$(jq -r '.persona' "$f")"
    done
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
  ok "Switched to ${_C_BOLD}${label}${_C_RST} (${lines} lines)"
}
