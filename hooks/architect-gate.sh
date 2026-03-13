#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Architect Gate Hook — enforces plan quality and task awareness
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PreToolUse on Write|Edit
# Purpose: Two gates:
#   1. Plan files MUST contain "## Architect Review" section
#      (blocks writes to .claude/plans/ without it)
#   2. First source file edit nudges task classification
#
# Exit 0 = allow, Exit 2 = block with message

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# --- Gate 1: Plan file must have Architect Review section ---
if [[ "$FILE_PATH" == *".claude/plans/"* ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
  if [ -n "$CONTENT" ]; then
    echo "$CONTENT" | grep -q "## Architect Review" && exit 0
    echo "BLOCKED: Plan file must include '## Architect Review' section. Run the appropriate domain architect agent first, then include findings." >&2
    exit 2
  fi

  NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
  if [ -n "$NEW_STRING" ]; then
    echo "$NEW_STRING" | grep -q "## Architect Review" && exit 0
    [ -f "$FILE_PATH" ] && grep -q "## Architect Review" "$FILE_PATH" && exit 0
    echo "BLOCKED: Plan file must include '## Architect Review' section. Run the appropriate domain architect agent first, then include findings." >&2
    exit 2
  fi
  exit 0
fi

# --- Gate 2: One-time nudge on first source file edit ---
# Skip non-source files (configs, docs, claude files, lock files)
[[ "$FILE_PATH" == *".claude/"* ]] && exit 0
[[ "$FILE_PATH" == *".md" ]] && exit 0
[[ "$FILE_PATH" == *".json" && "$FILE_PATH" != *"/src/"* ]] && exit 0
[[ "$FILE_PATH" == *".lock" ]] && exit 0
[[ "$FILE_PATH" == *"node_modules"* ]] && exit 0

MARKER="/tmp/claude-code-classified-${PPID}"
if [ ! -f "$MARKER" ]; then
  touch "$MARKER"
  echo "REMINDER: Have you classified this task? Significant tasks require EnterPlanMode and a domain architect review before implementation. If this is trivial/moderate, proceed." >&2
fi

exit 0