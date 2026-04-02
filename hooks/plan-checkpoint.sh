#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Plan Checkpoint Hook — nudge to reclaim context after planning
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PostToolUse on ExitPlanMode
# Purpose: After a plan is approved and plan mode exits, suggest
#          running /clear to start implementation with a full
#          context window. The plan file, CLAUDE.md, and auto-memory
#          all persist on disk and reload automatically.
#
# Advisory only — always exits 0, never blocks.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only fire for ExitPlanMode — matcher should handle this,
# but belt-and-suspenders in case of wildcard matchers.
[[ "$TOOL_NAME" != "ExitPlanMode" ]] && exit 0

jq -n --arg ctx "CHECKPOINT: Plan approved. Planning and architect review consume significant context. Consider /clear to start implementation with a fresh context window — your plan file, CLAUDE.md, and auto-memory all persist and reload automatically." '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
