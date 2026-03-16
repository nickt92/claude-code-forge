#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Forge Update Check Hook — one-per-session version check
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Trigger: UserPromptSubmit
# Purpose: Compares installed forge version against source version
#          and advises the user if an update is available.
#
# Purely local — reads versions from:
#   - Installed: manifest.json (forge_version field)
#   - Source: $FORGE_SOURCE_DIR/lib/manifest.sh (FORGE_VERSION variable)
#
# No network calls. Fires once per session via PPID marker.
#
# Exit code: Always 0 (advisory only)
#
# Note: set -e intentionally omitted — grep returns 1 on no-match,
# which is expected control flow in hook scripts.

INPUT=$(cat)

# ── One check per session ─────────────────────────────────────
MARKER="/tmp/claude-forge-update-${PPID}"
[ -f "$MARKER" ] && exit 0

# Clean up stale markers from old sessions (>24h)
find /tmp -maxdepth 1 -name "claude-forge-update-*" -mtime +1 -delete 2>/dev/null || true

touch "$MARKER"

# ── Read installed version from manifest ──────────────────────
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
MANIFEST_FILE="$CLAUDE_DIR/forge-backup/manifest.json"

[ -f "$MANIFEST_FILE" ] || exit 0

INSTALLED_VERSION=$(jq -r '.forge_version // empty' "$MANIFEST_FILE" 2>/dev/null)
[ -z "$INSTALLED_VERSION" ] && exit 0

# ── Read source version ──────────────────────────────────────
# Determine source directory from manifest
SOURCE_DIR=$(jq -r '.source_dir // empty' "$MANIFEST_FILE" 2>/dev/null)
[ -z "$SOURCE_DIR" ] && exit 0
[ -d "$SOURCE_DIR" ] || exit 0

SOURCE_MANIFEST="$SOURCE_DIR/lib/manifest.sh"
[ -f "$SOURCE_MANIFEST" ] || exit 0

SOURCE_VERSION=$(grep -oE 'FORGE_VERSION="\$\{FORGE_VERSION:-[^}]+\}"' "$SOURCE_MANIFEST" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

# Fallback: try simpler pattern
if [ -z "$SOURCE_VERSION" ]; then
  SOURCE_VERSION=$(grep -oE 'FORGE_VERSION[^0-9]*([0-9]+\.[0-9]+\.[0-9]+)' "$SOURCE_MANIFEST" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
fi

[ -z "$SOURCE_VERSION" ] && exit 0

# ── Compare versions ─────────────────────────────────────────
[ "$INSTALLED_VERSION" = "$SOURCE_VERSION" ] && exit 0

# Version mismatch — advise update
jq -n --arg installed "$INSTALLED_VERSION" --arg available "$SOURCE_VERSION" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("INFO: Forge update available. Installed: v" + $installed + ", available: v" + $available + ". Run '\''forge install'\'' to update.")
  }
}'

exit 0
