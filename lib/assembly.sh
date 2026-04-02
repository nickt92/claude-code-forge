#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Assembly — assembles CLAUDE.md from profile + section files
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required env vars:
#   SECTIONS_DIR  — path to templates/sections/ directory
#
# Required commands:
#   jq, cat
#
# Usage:
#   source lib/assembly.sh
#   assemble_claude_md "/path/to/profile.json" "/path/to/output.md"

assemble_claude_md() {
  local profile_file="$1"
  local output_file="$2"

  # Validate schema version
  local schema_ver
  schema_ver=$(jq -r '.schema_version // 0' "$profile_file")
  if [ "$schema_ver" -ne 1 ]; then
    echo "Unsupported profile schema version: $schema_ver (expected 1)" >&2
    return 1
  fi

  local comm auto work depth persona_name
  comm=$(jq -r '.axes.communication' "$profile_file")
  auto=$(jq -r '.axes.autonomy' "$profile_file")
  work=$(jq -r '.axes.workflow' "$profile_file")
  depth=$(jq -r '.axes.depth' "$profile_file")
  persona_name=$(jq -r '.persona' "$profile_file")

  # Validate axis values — prevent path traversal in section filenames
  local _axis_val
  for _axis_val in "$comm" "$auto" "$work" "$depth"; do
    if ! [[ "$_axis_val" =~ ^[a-z]+(-[a-z]+)*$ ]]; then
      echo "Invalid axis value: $_axis_val" >&2
      return 1
    fi
  done

  # Assemble by concatenating section files
  {
    echo "<!-- Assembled by Claude Code Forge | Profile: ${persona_name} | $(date +%Y-%m-%d) -->"
    echo ""
    cat "$SECTIONS_DIR/base.md"
    echo ""
    cat "$SECTIONS_DIR/communication-${comm}.md"
    echo ""
    cat "$SECTIONS_DIR/depth-${depth}.md"
    echo ""
    cat "$SECTIONS_DIR/autonomy-${auto}.md"
    echo ""
    cat "$SECTIONS_DIR/workflow-${work}.md"
    echo ""
    cat "$SECTIONS_DIR/quality-core.md"
    while IFS= read -r q; do
      [ -z "$q" ] && continue
      if [ "$q" != "core" ] && [ -f "$SECTIONS_DIR/quality-${q}.md" ]; then
        echo ""
        cat "$SECTIONS_DIR/quality-${q}.md"
      fi
    done < <(jq -r '.quality[]' "$profile_file")
  } > "$output_file"
}
