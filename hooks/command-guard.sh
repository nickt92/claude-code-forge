#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Command Guard Hook — blocks dangerous bash commands
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PreToolUse on Bash
# Purpose: Prevents destructive, dangerous, or insecure commands
#          from executing through Claude's Bash tool.
#
# Categories:
#   - Destructive deletion (rm -rf /, ~, $HOME, /*, .)
#   - Secret leakage (env|, printenv, cat .env piped)
#   - Command injection (eval $(, bash -c "$(curl")
#   - Remote code execution (curl|bash, wget|sh)
#   - Fork bombs
#   - Privilege escalation (chmod 777 on system paths)
#   - System damage (mkfs, dd to /dev/, kill -9 1)
#
# Exit 0 = allow, Exit 2 = block with message
#
# Note: set -e intentionally omitted — grep returns 1 on no-match,
# which is expected control flow in hook scripts.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Empty command — nothing to guard
[ -z "$COMMAND" ] && exit 0

# ── forge-override: user-confirmed bypass ─────────────────────
# Requires non-empty reason. Bare "# forge-override" is rejected.
# Bypasses ALL guard checks for the entire command — not just the
# triggering pattern. Security model depends on Claude Code's
# permission prompt showing the full command to the user.
# Duplicated in db-guard.sh — hooks must be self-contained (no shared sourcing).
if echo "$COMMAND" | head -1 | grep -qE '^# forge-override: .+'; then
  _OVERRIDE_REASON=$(echo "$COMMAND" | head -1 | sed 's/^# forge-override: //')
  _OVERRIDE_REASON=${_OVERRIDE_REASON//\"/\\\"}
  _OVERRIDE_CMD=$(echo "$COMMAND" | tail -n +2)
  _OVERRIDE_CMD=${_OVERRIDE_CMD//\"/\\\"}
  # Truncate at 500 chars for log readability but preserve full command visibility
  [ ${#_OVERRIDE_CMD} -gt 500 ] && _OVERRIDE_CMD="${_OVERRIDE_CMD:0:500}...[truncated]"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OVERRIDE_CONFIRMED reason=\"$_OVERRIDE_REASON\" command=\"$_OVERRIDE_CMD\"" \
    >> "$HOME/.claude/security.log"
  exit 0
fi

# ── Destructive deletion ──────────────────────────────────────
# Block rm targeting critical paths when both recursive and force flags are present.
# Handles short flags (-rf, -fr, -r -f) and long flags (--recursive, --force).
_rm_targets_critical_path() {
  echo "$1" | grep -qE '(\s/\s*$|\s/\*|\s~|\s"\$HOME"|\s\$HOME|\s\.)(\s|$)'
}
_rm_has_recursive() {
  echo "$1" | grep -qE '(^|\s)(-[a-zA-Z]*r[a-zA-Z]*\s|--recursive(\s|$))' ||
  echo "$1" | grep -qE '(^|\s)-[a-zA-Z]*r[a-zA-Z]*$'
}
_rm_has_force() {
  echo "$1" | grep -qE '(^|\s)(-[a-zA-Z]*f[a-zA-Z]*\s|--force(\s|$))' ||
  echo "$1" | grep -qE '(^|\s)-[a-zA-Z]*f[a-zA-Z]*$'
}
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?(command\s+)?rm\s' ; then
  rm_args="${COMMAND#*rm}"
  if _rm_targets_critical_path "$rm_args" && _rm_has_recursive "$rm_args" && _rm_has_force "$rm_args"; then
    echo "BLOCKED: Destructive deletion detected. The command attempts to recursively force-delete a critical path (/, ~, \$HOME, or current directory). Use targeted paths instead." >&2
    exit 2
  fi
fi

# ── Fork bombs ────────────────────────────────────────────────
if echo "$COMMAND" | grep -qE ':\(\)\s*\{.*:\|:.*\}'; then
  echo "BLOCKED: Fork bomb detected. This command would exhaust system resources." >&2
  exit 2
fi

# ── Remote code execution ─────────────────────────────────────
# Block curl/wget piped to bash/sh/zsh
if echo "$COMMAND" | grep -qE '(curl|wget)\s+.*\|\s*(bash|sh|zsh)'; then
  echo "BLOCKED: Remote code execution detected. Piping downloaded content directly to a shell is dangerous. Download first, review, then execute." >&2
  exit 2
fi

# ── Command injection ────────────────────────────────────────
# Block eval $(, bash -c "$(curl
if echo "$COMMAND" | grep -qE 'eval\s+(\$\(|"\$\()'; then
  echo "BLOCKED: Command injection risk. eval \$(...) can execute arbitrary code from subcommand output." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE 'bash\s+-c\s+.*\$\(\s*(curl|wget)'; then
  echo "BLOCKED: Command injection risk. bash -c with embedded curl/wget can execute arbitrary remote code." >&2
  exit 2
fi

# Block piping to bash/sh/zsh (general pattern, not just curl/wget)
if echo "$COMMAND" | grep -qE '\|\s*(bash|sh|zsh)\s*$'; then
  echo "BLOCKED: Piping output to a shell interpreter is dangerous. Review the output first." >&2
  exit 2
fi

# ── Secret leakage ────────────────────────────────────────────
# Block env/printenv piped (leak all environment variables)
if echo "$COMMAND" | grep -qE '(^|\s)(env|printenv)\s*\|'; then
  echo "BLOCKED: Secret leakage risk. Piping env/printenv output may expose secrets. Access specific variables instead." >&2
  exit 2
fi

# Block cat .env / .env.* piped
if echo "$COMMAND" | grep -qE 'cat\s+\.env[.a-zA-Z0-9_-]*\s*\|'; then
  echo "BLOCKED: Secret leakage risk. Piping .env contents may expose secrets." >&2
  exit 2
fi

# Block cat ~/.ssh/* piped
if echo "$COMMAND" | grep -qE 'cat\s+~/\.ssh/\S+\s*\|'; then
  echo "BLOCKED: Secret leakage risk. Piping SSH key contents may expose private keys." >&2
  exit 2
fi

# ── Privilege escalation ──────────────────────────────────────
# Block chmod 777 or chmod -R/--recursive 777 on system paths
if echo "$COMMAND" | grep -qE 'chmod\s+(--recursive\s+|-R\s+)?777\s+/'; then
  echo "BLOCKED: Privilege escalation risk. chmod 777 on system paths creates security vulnerabilities. Use specific permissions (e.g., 755, 644)." >&2
  exit 2
fi

# ── System damage ─────────────────────────────────────────────
# Block mkfs (format filesystems)
if echo "$COMMAND" | grep -qE '(^|\s)mkfs'; then
  echo "BLOCKED: System damage risk. mkfs formats filesystems and destroys all data on the target device." >&2
  exit 2
fi

# Block dd to /dev/ (raw device writes)
if echo "$COMMAND" | grep -qE 'dd\s+.*of=/dev/'; then
  echo "BLOCKED: System damage risk. dd writing to /dev/ devices can destroy data or damage the system." >&2
  exit 2
fi

# Block kill -9 1 (init process)
if echo "$COMMAND" | grep -qE 'kill\s+-9\s+1(\s|$)'; then
  echo "BLOCKED: System damage risk. Killing PID 1 (init/systemd) will crash the system." >&2
  exit 2
fi

# ── Deep scan: destructive patterns inside shell wrappers ─────
# Catches patterns like: bash -c 'rm -rf /', sh -c "dd of=/dev/sda"
# These bypass prefix-based checks above when wrapped in a shell invocation.
if echo "$COMMAND" | grep -qE '(bash|sh|zsh)\s+-c\s'; then
  _INNER=$(echo "$COMMAND" | sed -E "s/.*((bash|sh|zsh)\s+-c\s+['\"]?)//" | sed -E "s/['\"]?\s*$//")
  # Destructive rm on critical paths
  if echo "$_INNER" | grep -qE 'rm\s+' && echo "$_INNER" | grep -qE '(\s/\s*$|\s/\*|\s~|\s\$HOME|\s\.)(\s|$)'; then
    if echo "$_INNER" | grep -qE '(-[a-zA-Z]*r|--recursive)' && echo "$_INNER" | grep -qE '(-[a-zA-Z]*f|--force)'; then
      echo "BLOCKED: Destructive deletion detected inside shell wrapper. The command attempts to recursively force-delete a critical path." >&2
      exit 2
    fi
  fi
  # mkfs inside wrapper
  if echo "$_INNER" | grep -qE '(^|\s)mkfs'; then
    echo "BLOCKED: System damage risk detected inside shell wrapper." >&2
    exit 2
  fi
  # dd to /dev/ inside wrapper
  if echo "$_INNER" | grep -qE 'dd\s+.*of=/dev/'; then
    echo "BLOCKED: System damage risk detected inside shell wrapper." >&2
    exit 2
  fi
fi

exit 0
