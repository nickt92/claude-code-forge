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
# Blocked patterns (case-insensitive):
#   - DROP TABLE / DROP DATABASE / DROP SCHEMA
#   - TRUNCATE
#   - DELETE FROM without WHERE clause
#   - ALTER TABLE ... DROP
#
# Allowed:
#   - SELECT, INSERT, UPDATE (with WHERE), CREATE, etc.
#   - DELETE FROM ... WHERE ... (has WHERE clause)
#   - Commands not targeting a database CLI
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

# Fast path: exit immediately if no database CLI is involved
echo "$COMMAND" | grep -qE '(psql|mysql|sqlite3|mongosh)' || exit 0

# ── DROP TABLE / DATABASE / SCHEMA ────────────────────────────
if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|SCHEMA)'; then
  echo "BLOCKED: Destructive SQL detected. DROP TABLE/DATABASE/SCHEMA will permanently delete data. Use a migration tool or back up first." >&2
  exit 2
fi

# ── TRUNCATE ──────────────────────────────────────────────────
if echo "$COMMAND" | grep -qiE 'TRUNCATE\s'; then
  echo "BLOCKED: Destructive SQL detected. TRUNCATE will delete all rows from the table. Use DELETE with a WHERE clause for targeted removal." >&2
  exit 2
fi

# ── DELETE FROM without WHERE ─────────────────────────────────
# Block DELETE FROM <table> that lacks a WHERE clause
if echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s+'; then
  if ! echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s+\S+\s+WHERE\s'; then
    echo "BLOCKED: Destructive SQL detected. DELETE FROM without a WHERE clause will delete all rows. Add a WHERE clause to target specific rows." >&2
    exit 2
  fi
fi

# ── ALTER TABLE ... DROP ──────────────────────────────────────
if echo "$COMMAND" | grep -qiE 'ALTER\s+TABLE\s+.*\sDROP\s'; then
  echo "BLOCKED: Destructive SQL detected. ALTER TABLE ... DROP will permanently remove a column or constraint. Use a migration tool for schema changes." >&2
  exit 2
fi

exit 0
