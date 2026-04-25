#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Backup Transcript Hook — preserves context before compaction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PreCompact (fires before Claude compresses context)
# Purpose: Copies the full session transcript to ~/.claude/backups/
#          so you never lose context history.
#
# Cleanup: delegated to Claude Code's cleanupPeriodDays setting.

set -euo pipefail

BACKUP_DIR="$HOME/.claude/backups"
mkdir -p "$BACKUP_DIR"

# Windows jq compat — strip \r from output (see lib/platform.sh)
[[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]] && jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')

# Sanitize to prevent path traversal in backup filename
SESSION_ID="${SESSION_ID//[^a-zA-Z0-9_-]/_}"
TRIGGER="${TRIGGER//[^a-zA-Z0-9_-]/_}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ -f "$TRANSCRIPT_PATH" ]; then
  cp "$TRANSCRIPT_PATH" "$BACKUP_DIR/${SESSION_ID}-${TRIGGER}-${TIMESTAMP}.jsonl"
fi

exit 0