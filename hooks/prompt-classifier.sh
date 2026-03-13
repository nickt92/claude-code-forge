#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Prompt Classifier Hook — session-start task awareness nudge
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: UserPromptSubmit
# Purpose: On the first prompt of every session, reminds Claude
#          to classify the task (trivial/moderate/significant)
#          before starting work. The classification itself is
#          Claude's job — this hook just ensures it happens.
#
# Fires once per session using a PPID-based marker.
# A new terminal / new `claude` invocation = new session = fires again.

INPUT=$(cat)

# One nudge per session — PPID is tied to the parent shell
MARKER="/tmp/claude-code-prompted-${PPID}"
[ -f "$MARKER" ] && exit 0
touch "$MARKER"

jq -n '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: "SYSTEM: Before starting work, classify this task as trivial, moderate, or significant per your workflow rules. If significant, use EnterPlanMode and invoke the domain architect before implementation. Check which branch you are on — NEVER work directly on main or develop without creating a feature branch first."
  }
}'

exit 0