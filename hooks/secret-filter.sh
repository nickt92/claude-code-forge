#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Secret Filter Hook — advisory credential detection
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PostToolUse (all tools, matcher: "")
# Purpose: Scans tool output for leaked secrets and warns Claude
#          not to repeat them. Advisory only — PostToolUse cannot
#          block or mask non-MCP output.
#
# Detected patterns:
#   - AWS access keys (AKIA...)
#   - GitHub tokens (ghp_, ghs_, github_pat_)
#   - OpenAI/Anthropic keys (sk-...)
#   - Slack tokens (xoxb-, xoxp-, etc.)
#   - NPM tokens (npm_...)
#   - Bearer tokens
#   - Private keys (PEM and OpenSSH)
#   - Database connection URLs with credentials
#   - JWT tokens
#   - Stripe keys (sk_live_, pk_live_)
#   - Generic KEY/SECRET/TOKEN/PASSWORD env assignments
#
# Exit code: Always 0 (advisory only)
# Output: JSON with additionalContext warning on detection
# Side effect: Logs detections to ~/.claude/security.log
#
# Note: set -e intentionally omitted — grep returns 1 on no-match,
# which is expected control flow in hook scripts.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty')

# No response to scan
[ -z "$TOOL_RESPONSE" ] && exit 0

# ── Pattern matching ──────────────────────────────────────────
DETECTED=""

# AWS access keys
if echo "$TOOL_RESPONSE" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  DETECTED="${DETECTED}AWS access key, "
fi

# GitHub tokens
if echo "$TOOL_RESPONSE" | grep -qE 'gh[ps]_[A-Za-z0-9_]{36,}'; then
  DETECTED="${DETECTED}GitHub token, "
fi
if echo "$TOOL_RESPONSE" | grep -qE 'github_pat_[A-Za-z0-9_]+'; then
  DETECTED="${DETECTED}GitHub PAT, "
fi

# OpenAI/Anthropic API keys
if echo "$TOOL_RESPONSE" | grep -qE 'sk-[A-Za-z0-9_-]{20,}'; then
  DETECTED="${DETECTED}API key (sk-), "
fi

# Slack tokens (require 10+ chars after prefix to avoid self-matching on regex strings)
if echo "$TOOL_RESPONSE" | grep -qE 'xox[bpras]-[a-zA-Z0-9_/-]{10,}'; then
  DETECTED="${DETECTED}Slack token, "
fi

# NPM tokens
if echo "$TOOL_RESPONSE" | grep -qE 'npm_[A-Za-z0-9]{36,}'; then
  DETECTED="${DETECTED}NPM token, "
fi

# Bearer tokens (long)
if echo "$TOOL_RESPONSE" | grep -qE 'Bearer [A-Za-z0-9_.+/=-]{20,}'; then
  DETECTED="${DETECTED}Bearer token, "
fi

# Private keys (PEM format)
if echo "$TOOL_RESPONSE" | grep -qE '\-{5}BEGIN.*PRIVATE KEY\-{5}'; then
  DETECTED="${DETECTED}private key, "
fi

# Database connection strings with embedded credentials
if echo "$TOOL_RESPONSE" | grep -qE '(postgres|mysql|mongodb(\+srv)?|redis|amqp)://[^[:space:]]+:[^[:space:]]+@'; then
  DETECTED="${DETECTED}database URL with credentials, "
fi

# JWT tokens (three base64 segments separated by dots)
if echo "$TOOL_RESPONSE" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+'; then
  DETECTED="${DETECTED}JWT token, "
fi

# OpenSSH private keys
if echo "$TOOL_RESPONSE" | grep -qF 'BEGIN OPENSSH PRIVATE KEY'; then
  DETECTED="${DETECTED}OpenSSH private key, "
fi

# Stripe secret keys
if echo "$TOOL_RESPONSE" | grep -qE '(sk|pk|rk)_live_[A-Za-z0-9]{10,}'; then
  DETECTED="${DETECTED}Stripe key, "
fi

# Generic env-style secrets (require 1+ prefix chars to avoid bare keyword matches)
if echo "$TOOL_RESPONSE" | grep -qE '[A-Z_]+(KEY|SECRET|TOKEN|PASSWORD)=[^[:space:]]{16,}'; then
  DETECTED="${DETECTED}env secret, "
fi

# No secrets found — pass through silently
[ -z "$DETECTED" ] && exit 0

# Trim trailing comma-space
DETECTED="${DETECTED%, }"

# ── Log detection ─────────────────────────────────────────────
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
LOG_DIR="${CLAUDE_DIR:-$HOME/.claude}"
LOG_FILE="$LOG_DIR/security.log"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SECRET_DETECTED tool=$TOOL_NAME types=\"$DETECTED\"" >> "$LOG_FILE" 2>/dev/null

# ── Advisory output ───────────────────────────────────────────
jq -n --arg types "$DETECTED" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("SECURITY WARNING: Potential secrets detected in tool output (" + $types + "). Do NOT repeat, log, or include these values in your response. If you need to reference them, use placeholder text like [REDACTED].")
  }
}'

exit 0
