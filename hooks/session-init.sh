#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Session Init Hook — persona-aware task classification nudge
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: UserPromptSubmit
# Purpose: On the first prompt of every session, nudges Claude
#          to classify the task — with language adapted to the
#          user's persona (guided/moderate/high autonomy).
#
# Reads ~/.claude/profile.json for persona context.
# Falls back to generic nudge if profile is missing.
#
# Fires once per session using a PPID-based marker.
# A new terminal / new `claude` invocation = new session.

# Note: set -e intentionally omitted — grep/jq returns non-zero on no-match,
# which is expected control flow in hook scripts.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)

# One nudge per session — PPID is tied to the parent shell
_TMPDIR="${TMPDIR:-/tmp}"
MARKER="${_TMPDIR}/claude-code-prompted-${PPID}"
[ -f "$MARKER" ] && exit 0

# New session — clean up stale markers from old sessions (>24h)
# Also cleans architect-gate classified markers (created by architect-gate.sh)
find "$_TMPDIR" -maxdepth 1 -name "claude-code-prompted-*" -mtime +1 -delete 2>/dev/null || true
find "$_TMPDIR" -maxdepth 1 -name "claude-code-classified-*" -mtime +1 -delete 2>/dev/null || true

touch "$MARKER"

# Read persona context
PROFILE="$HOME/.claude/profile.json"
AUTONOMY="high"
LABEL=""
PERSONA=""
COMM=""
DEPTH=""

if [ -f "$PROFILE" ]; then
  AUTONOMY=$(jq -r '.axes.autonomy // "high"' "$PROFILE" 2>/dev/null)
  LABEL=$(jq -r '.label // ""' "$PROFILE" 2>/dev/null)
  PERSONA=$(jq -r '.persona // ""' "$PROFILE" 2>/dev/null)
  COMM=$(jq -r '.axes.communication // ""' "$PROFILE" 2>/dev/null)
  DEPTH=$(jq -r '.axes.depth // ""' "$PROFILE" 2>/dev/null)
fi

# Build persona hint (if available)
PERSONA_HINT=""
if [ -n "$LABEL" ] && [ -n "$PERSONA" ]; then
  PERSONA_HINT="You are working with a ${LABEL} (${PERSONA}). Communication: ${COMM}, Depth: ${DEPTH}. "
fi

# Branch protection (all personas)
BRANCH_REMINDER="Check which branch you are on — NEVER work directly on main or develop without creating a feature branch first."

# Autonomy-adapted classification nudge
case "$AUTONOMY" in
  guided)
    NUDGE="Assess complexity internally. If this involves multiple components, design your approach and walk me through it in plain language before starting."
    ;;
  moderate)
    NUDGE="Classify this task. If it's complex, outline your approach. If straightforward, proceed."
    ;;
  *)
    NUDGE="Classify as trivial/moderate/significant per your workflow rules. If significant, use EnterPlanMode and invoke the domain architect before implementation."
    ;;
esac

jq -n --arg ctx "SYSTEM: ${PERSONA_HINT}${NUDGE} ${BRANCH_REMINDER}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0