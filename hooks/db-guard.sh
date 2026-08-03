#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Database Guard Hook — blocks destructive SQL via bash CLIs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PreToolUse on Bash
# Purpose: Prevents destructive SQL statements from being executed
#          through database CLI tools (psql, mysql, sqlite3, mongosh).
#
# Guards CLI database clients via Bash. Does NOT guard MCP database
# tools — extend with additional PreToolUse matchers for specific
# MCP tool names (e.g., mcp__postgres__query) in a future version.
#
# Guarded patterns (case-insensitive):
#   - DROP TABLE / DROP DATABASE / DROP SCHEMA
#   - TRUNCATE
#   - DELETE FROM without WHERE clause
#   - ALTER TABLE ... DROP
#   - COPY ... TO/FROM PROGRAM  (SQL-to-shell execution)
#
# Allowed:
#   - SELECT, INSERT, UPDATE (with WHERE), CREATE, etc.
#   - DELETE FROM ... WHERE ... (has WHERE clause)
#   - Commands not targeting a database CLI
#
# This stays a hook because SQL semantics are genuinely unexpressible as a
# permission rule: Bash(psql:*) cannot tell SELECT from DROP TABLE.
#
# Decisions are permissionDecision "ask", not exit 2. Every pattern here has a
# legitimate use — dropping a table in a dev database is ordinary work — so the
# right answer is a prompt showing the real statement, not a block the user
# then needs an override to get past. That is also why forge-override is gone:
# its security model assumed a permission prompt the user would see, and when
# the command is allowlisted there is no prompt at all.
#
# Note: set -e intentionally omitted — grep returns 1 on no-match,
# which is expected control flow in hook scripts.

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)
_HOOK_START=$SECONDS
_DG_TMPDIR="${TMPDIR:-/tmp}"
_DG_LOG_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# ── Log hygiene ───────────────────────────────────────────────
# forge shipped secret-filter to protect the user's tool output while writing
# its own logs world-readable (0644) and unbounded. Appends now create the file
# with owner-only permissions and roll it at 1 MB.
#
# Duplicated across hooks on purpose: each one is copied into ~/.claude/hooks/
# and runs standalone, with no shared library to source.
_dg_append() {
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

_dg_log() {
  local dur=$(( (SECONDS - _HOOK_START) * 1000 ))
  _dg_append "${TMPDIR:-/tmp}/forge-session-log-${PPID}" \
    "$(date +%s)|db-guard|${dur}|$1"
  _dg_append "${_DG_LOG_DIR}/hook-telemetry.log" \
    "$(date +%s)|db-guard|${dur}|$1"
}

# Fail open, but say so. With jq missing this hook silently exited 0 forever
# and nothing distinguished "nothing to guard" from "could not look".
_dg_degraded() {
  _dg_append "${_DG_LOG_DIR}/security.log" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ) DEGRADED hook=db-guard reason=\"$1\""
  _dg_log degraded
  exit 0
}

command -v jq >/dev/null 2>&1 || _dg_degraded "jq not found; SQL not inspected"

# grep carries every pattern below, so its presence is not the question —
# whether it works is. A shim on PATH satisfies `command -v` and then silently
# makes every check match nothing.
printf 'forge' | grep -q '^forge$' 2>/dev/null \
  || _dg_degraded "grep unusable; SQL not inspected"

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) \
  || _dg_degraded "could not parse hook input"

# Empty command — nothing to guard
[ -z "$COMMAND" ] && { _dg_log allow; exit 0; }

_dg_ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  _dg_log ask
  exit 0
}

# Fast path: exit immediately if no database CLI is involved
printf '%s' "$COMMAND" | grep -qE '(psql|mysql|sqlite3|mongosh)' || { _dg_log allow; exit 0; }

# ── COPY ... TO/FROM PROGRAM ──────────────────────────────────
# Postgres runs the argument as a shell command with the server's privileges.
# This is SQL-to-RCE, and no Bash rule models it — Bash(psql:*) sees a database
# client, not a shell. Checked first because it is the one that is never a
# schema mistake.
if printf '%s' "$COMMAND" | grep -qiE 'COPY\s+.*\s(TO|FROM)\s+PROGRAM\b'; then
  _dg_ask "COPY ... TO/FROM PROGRAM executes a shell command on the database server. This is remote code execution, not a query."
fi

# ── DROP TABLE / DATABASE / SCHEMA ────────────────────────────
if printf '%s' "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|SCHEMA)'; then
  _dg_ask "DROP TABLE/DATABASE/SCHEMA permanently deletes data. Confirm the target is what you expect, and that it is not production."
fi

# ── TRUNCATE ──────────────────────────────────────────────────
if printf '%s' "$COMMAND" | grep -qiE 'TRUNCATE\s'; then
  _dg_ask "TRUNCATE deletes every row in the table and is not transactional on all engines."
fi

# ── DELETE FROM without WHERE ─────────────────────────────────
# Checked per statement. Two whole-command greps let a qualified delete vouch
# for an unqualified one in the same batch: `DELETE FROM a WHERE id=1;
# DELETE FROM b` deleted every row of b and was allowed, and batching like that
# in one psql -c is entirely normal.
if printf '%s' "$COMMAND" | grep -qiE 'DELETE[[:space:]]+FROM[[:space:]]+'; then
  _dg_stmt_unqualified=false
  while IFS= read -r _dg_stmt; do
    printf '%s' "$_dg_stmt" | grep -qiE 'DELETE[[:space:]]+FROM[[:space:]]+' || continue
    # A WHERE anywhere after the table reference qualifies the statement; the
    # table may carry an alias or a schema prefix.
    printf '%s' "$_dg_stmt" | grep -qiE 'DELETE[[:space:]]+FROM[[:space:]]+.*[[:space:](]WHERE[[:space:](]' \
      || _dg_stmt_unqualified=true
  done <<EOF
$(printf '%s' "$COMMAND" | tr ';' '\n')
EOF
  if [ "$_dg_stmt_unqualified" = true ]; then
    _dg_ask "DELETE FROM with no WHERE clause removes every row in the table."
  fi
fi

# ── ALTER TABLE ... DROP ──────────────────────────────────────
if printf '%s' "$COMMAND" | grep -qiE 'ALTER[[:space:]]+TABLE[[:space:]]+.*[[:space:]]DROP[[:space:]]'; then
  _dg_ask "ALTER TABLE ... DROP permanently removes a column or constraint, and the data in it."
fi

# ── MongoDB destructive operations ────────────────────────────
# mongosh speaks JavaScript, not SQL, so none of the patterns above ever
# matched it — while the hook header and SECURITY.md both claimed it was
# guarded.
if printf '%s' "$COMMAND" | grep -qE '\.drop[[:space:]]*\(|dropDatabase[[:space:]]*\(|dropIndexes?[[:space:]]*\('; then
  _dg_ask "This drops a MongoDB collection, index, or database. The data is not recoverable without a backup."
fi

if printf '%s' "$COMMAND" | grep -qE '(deleteMany|remove)[[:space:]]*\([[:space:]]*(\{[[:space:]]*\})?[[:space:]]*\)'; then
  _dg_ask "This removes every document in the collection — the filter is empty."
fi

_dg_log allow; exit 0
