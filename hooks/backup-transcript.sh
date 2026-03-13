#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Backup Transcript Hook — preserves context before compaction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: PreCompact (fires before Claude compresses context)
# Purpose: Copies the full session transcript to ~/.claude/backups/
#          so you never lose context history.
#
# Auto-cleanup: removes backups older than 30 days on each run.

set -euo pipefail

BACKUP_DIR="$HOME/.claude/backups"
mkdir -p "$BACKUP_DIR"

# Prune backups older than 30 days
find "$BACKUP_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ -f "$TRANSCRIPT_PATH" ]; then
  cp "$TRANSCRIPT_PATH" "$BACKUP_DIR/${SESSION_ID}-${TRIGGER}-${TIMESTAMP}.jsonl"
fi

exit 0