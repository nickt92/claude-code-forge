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

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)
_HOOK_START=$SECONDS
_AG_TMPDIR="${TMPDIR:-/tmp}"

_ag_log() {
  local outcome="$1"
  local dur=$(( (SECONDS - _HOOK_START) * 1000 ))
  printf '%s|architect-gate|%s|%s\n' "$(date +%s)" "$dur" "$outcome" >> "${_AG_TMPDIR}/forge-session-log-${PPID}" 2>/dev/null
  printf '%s|architect-gate|%s|%s\n' "$(date +%s)" "$dur" "$outcome" >> "$HOME/.claude/hook-telemetry.log" 2>/dev/null
}

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# --- Gate 1: Plan file must have Architect Review section ---
if [[ "$FILE_PATH" == *".claude/plans/"* ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
  if [ -n "$CONTENT" ]; then
    echo "$CONTENT" | grep -q "## Architect Review" && { _ag_log allow; exit 0; }
    echo "BLOCKED: Plan file must include '## Architect Review' section. Run the appropriate domain architect agent first, then include findings." >&2
    _ag_log block; exit 2
  fi

  NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
  if [ -n "$NEW_STRING" ]; then
    echo "$NEW_STRING" | grep -q "## Architect Review" && { _ag_log allow; exit 0; }
    [ -f "$FILE_PATH" ] && grep -q "## Architect Review" "$FILE_PATH" && { _ag_log allow; exit 0; }
    echo "BLOCKED: Plan file must include '## Architect Review' section. Run the appropriate domain architect agent first, then include findings." >&2
    _ag_log block; exit 2
  fi
  _ag_log allow; exit 0
fi

# --- Shared: skip non-source files --------------------------------
[[ "$FILE_PATH" == *".claude/"* ]] && { _ag_log allow; exit 0; }
[[ "$FILE_PATH" == *".md" ]] && { _ag_log allow; exit 0; }
[[ "$FILE_PATH" == *".json" && "$FILE_PATH" != *"/src/"* ]] && { _ag_log allow; exit 0; }
[[ "$FILE_PATH" == *".lock" ]] && { _ag_log allow; exit 0; }
[[ "$FILE_PATH" == *"node_modules"* ]] && { _ag_log allow; exit 0; }

# --- Gate 0: Plan enforcement (blocks unplanned significant work) ---
STATE_FILE="${_AG_TMPDIR}/forge-session-state-${PPID}"
_CLASSIFICATION="unknown"
_PHASE=""

if [ -f "$STATE_FILE" ]; then
  _CLASSIFICATION=$(grep '^classification=' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
  _PHASE=$(grep '^phase=' "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
  [ -z "$_CLASSIFICATION" ] && _CLASSIFICATION="unknown"
fi

# If already past planning, allow through
[ "$_PHASE" = "implementation" ] && { _ag_log allow; exit 0; }

# Read planning enforcement level from profile (default: nudge)
PROFILE="$HOME/.claude/profile.json"
_ENFORCEMENT="nudge"
if [ -f "$PROFILE" ]; then
  _PE=$(jq -r '.planning_enforcement // empty' "$PROFILE" 2>/dev/null)
  [ -n "$_PE" ] && _ENFORCEMENT="$_PE"
fi

# enforcement=off → skip gate entirely
[ "$_ENFORCEMENT" = "off" ] && { _ag_log allow; exit 0; }

# Check for existing plan files
_HAS_PLAN=false
if [ -d "$HOME/.claude/plans" ]; then
  for _pf in "$HOME/.claude/plans"/*.md; do
    [ -f "$_pf" ] && { _HAS_PLAN=true; break; }
  done
fi

if [ "$_CLASSIFICATION" = "unknown" ] && [ "$_HAS_PLAN" = false ]; then
  if [ "$_ENFORCEMENT" = "enforce" ]; then
    echo "BLOCKED: No plan file found and task is unclassified. Classify the task first — if significant, use EnterPlanMode and invoke the domain architect before editing source files." >&2
    _ag_log block; exit 2
  fi
  # enforcement=nudge falls through to Gate 2 below
fi

# --- Gate 2: One-time nudge on first source file edit ---
MARKER="${_AG_TMPDIR}/claude-code-classified-${PPID}"
if [ ! -f "$MARKER" ]; then
  touch "$MARKER"
  echo "REMINDER: Have you classified this task? Significant tasks require EnterPlanMode and a domain architect review before implementation. If this is trivial/moderate, proceed." >&2
fi

_ag_log allow; exit 0