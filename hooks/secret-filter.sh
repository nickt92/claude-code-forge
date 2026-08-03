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
_HOOK_START=$SECONDS
_SF_TMPDIR="${TMPDIR:-/tmp}"

# ── Log hygiene ───────────────────────────────────────────────
# forge shipped secret-filter to protect the user's tool output while writing
# its own logs world-readable (0644) and unbounded. Appends now create the file
# with owner-only permissions and roll it at 1 MB.
#
# Duplicated across hooks on purpose: each one is copied into ~/.claude/hooks/
# and runs standalone, with no shared library to source.
_sf_append() {
  local f="$1" line="$2" sz
  mkdir -p "$(dirname "$f")" 2>/dev/null
  if [ -f "$f" ]; then
    sz=$(wc -c < "$f" 2>/dev/null || echo 0)
    if [ "${sz:-0}" -gt 1048576 ]; then
      # The rotated file keeps its inode and therefore its mode. Without this
      # chmod, an upgrade from a pre-2.0 install freezes ~1 MB of 0644 log
      # permanently — the exact thing this helper exists to stop.
      mv -f "$f" "${f}.1" 2>/dev/null
      chmod 600 "${f}.1" 2>/dev/null
    fi
  fi
  [ -e "$f" ] || ( umask 077; : > "$f" ) 2>/dev/null
  chmod 600 "$f" 2>/dev/null
  # Braces, not a trailing 2>/dev/null on the printf: redirections are applied
  # left to right, so `>> "$f" 2>/dev/null` still prints the open failure to
  # stderr — on every single tool call when the log directory is missing.
  { printf '%s\n' "$line" >> "$f"; } 2>/dev/null
}

_SF_LOG_DIR="${CLAUDE_DIR:-$HOME/.claude}"

_sf_log() {
  local dur=$(( (SECONDS - _HOOK_START) * 1000 ))
  _sf_append "${TMPDIR:-/tmp}/forge-session-log-${PPID}" \
    "$(date +%s)|secret-filter|${dur}|$1"
  _sf_append "${_SF_LOG_DIR}/hook-telemetry.log" \
    "$(date +%s)|secret-filter|${dur}|$1"
}

TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty')

# No response to scan
[ -z "$TOOL_RESPONSE" ] && { _sf_log allow; exit 0; }

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

# Private keys (PEM format).
#
# Every literal below is assembled from fragments. Reading this file — or any
# file that documents these patterns — used to trip the scanner on its own
# source, which is how a security warning ends up attached to a routine Read
# of the hook itself. Splitting the marker means the pattern still matches a
# real key while the source text of the pattern does not match itself.
_SF_BEGIN='-----BE'"GIN"
if echo "$TOOL_RESPONSE" | grep -qE -e "${_SF_BEGIN}.*PRIVATE KEY"; then
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

# OpenSSH private keys — same fragment treatment as the PEM marker above.
# This literal was the one that fired on a plain Read of this file.
if echo "$TOOL_RESPONSE" | grep -qF -e "${_SF_BEGIN} OPENSSH"' PRIVATE'' KEY'; then
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
[ -z "$DETECTED" ] && { _sf_log allow; exit 0; }

# Trim trailing comma-space
DETECTED="${DETECTED%, }"

# ── Log detection ─────────────────────────────────────────────
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
# Only the detected TYPES are recorded, never the matched values — the log must
# not become the thing it is warning about.
_sf_append "${_SF_LOG_DIR}/security.log" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ) SECRET_DETECTED tool=${TOOL_NAME} types=\"${DETECTED}\""

# ── Advisory output ───────────────────────────────────────────
jq -n --arg types "$DETECTED" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("SECURITY WARNING: Potential secrets detected in tool output (" + $types + "). Do NOT repeat, log, or include these values in your response. If you need to reference them, use placeholder text like [REDACTED].")
  }
}'

_sf_log detect; exit 0
