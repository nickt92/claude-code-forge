#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Context Budget Guardian — protect context after planning
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Two modes, selected by $1:
#
#   exitplan   — PostToolUse on ExitPlanMode
#                Drops a PPID marker so PreCompact knows a plan
#                was just approved.
#
#   precompact — PreCompact (can block)
#                If marker exists: BLOCK (exit 2) — compacting
#                right after planning wastes the context window.
#                Suggests /clear instead.
#                Otherwise: ALLOW (exit 0).
#
# The marker auto-expires: each invocation checks mtime and
# ignores markers older than 10 minutes.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)

MODE="${1:-precompact}"
_TMPDIR="${TMPDIR:-/tmp}"
MARKER="${_TMPDIR}/claude-code-plan-approved-${PPID}"

case "$MODE" in
  exitplan)
    # Drop marker — PreCompact will check for it.
    # If touch fails (read-only TMPDIR), the protection window is silently
    # voided — precompact will allow compaction. This is acceptable degradation
    # for a developer tool; the /clear suggestion still appears in the advisory.
    [[ -L "$MARKER" ]] && rm -f "$MARKER"  # prevent symlink attacks
    touch "$MARKER"

    # Update session state — significant task completed planning
    STATE_FILE="${_TMPDIR}/forge-session-state-${PPID}"
    printf 'classification=significant\nphase=implementation\n' > "$STATE_FILE" 2>/dev/null || true

    jq -n --arg ctx "CHECKPOINT: Plan approved. Planning and architect review consume significant context. Consider /clear to start implementation with a fresh context window — your plan file, CLAUDE.md, and auto-memory all persist and reload automatically." '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
      }
    }'
    exit 0
    ;;

  precompact)
    # Check for recent plan-approved marker
    if [ -f "$MARKER" ]; then
      # Expire markers older than 10 minutes
      marker_age=0
      if [[ "$OSTYPE" == darwin* ]]; then
        marker_mtime=$(stat -f %m "$MARKER" 2>/dev/null || echo 0)
      else
        marker_mtime=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
      fi
      now=$(date +%s)
      marker_age=$(( now - marker_mtime ))

      if [ "$marker_age" -lt 600 ]; then
        # Plan was just approved — block compaction
        jq -n --arg msg "Plan just approved. Run /clear to start implementation with full context — compaction will lose planning context." '{
          hookSpecificOutput: {
            hookEventName: "PreCompact",
            suppressOutput: true
          },
          decision: "block",
          reason: $msg
        }'
        exit 2
      else
        # Marker is stale — clean up and allow
        rm -f "$MARKER"
      fi
    fi

    # No marker — allow compaction
    exit 0
    ;;
esac

exit 0
