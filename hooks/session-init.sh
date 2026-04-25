#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Session Init Hook — task classification nudge
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: UserPromptSubmit
# Purpose: On the first prompt of every session, nudges Claude
#          to classify the task — with language adapted to the
#          user's autonomy level (guided/moderate/high).
#
# Reads ~/.claude/profile.json for autonomy level.
# Falls back to high autonomy if profile is missing.
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

# Read autonomy level from profile
PROFILE="$HOME/.claude/profile.json"
AUTONOMY="high"

if [ -f "$PROFILE" ]; then
  AUTONOMY=$(jq -r '.axes.autonomy // "high"' "$PROFILE" 2>/dev/null)
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

jq -n --arg ctx "SYSTEM: ${NUDGE} ${BRANCH_REMINDER}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0