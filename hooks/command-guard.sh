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

# ── Destructive deletion ──────────────────────────────────────
# Block rm with both -r and -f (combined or separated) targeting critical paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|-[a-zA-Z]*r\s+-[a-zA-Z]*f|-[a-zA-Z]*f\s+-[a-zA-Z]*r)\s+(/\s*$|/\*|~|"\$HOME"|\$HOME|\.)(\s|$)'; then
  echo "BLOCKED: Destructive deletion detected. The command attempts to recursively force-delete a critical path (/, ~, \$HOME, or current directory). Use targeted paths instead." >&2
  exit 2
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
if echo "$COMMAND" | grep -qE 'eval\s+\$\('; then
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
# Block chmod 777 or chmod -R 777 on system paths
if echo "$COMMAND" | grep -qE 'chmod\s+(-R\s+)?777\s+/'; then
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

exit 0
