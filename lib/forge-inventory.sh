#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Forge Inventory — runtime discovery of shipped files
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Scans source directories to determine what forge ships.
# Single source of truth for health checks, best-effort uninstall,
# and tests — adding a file to the source directory automatically
# picks it up everywhere.
#
# Usage:
#   source lib/forge-inventory.sh
#
# Public API:
#   forge_shipped_rules    — newline-separated basenames (without .md)
#   forge_shipped_hooks    — newline-separated basenames (without .sh)
#   forge_shipped_scripts  — newline-separated basenames (without .sh)

FORGE_SOURCE_DIR="${FORGE_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Files installed directly to ~/.claude/ (not in subdirectories)
FORGE_ROOT_FILES=(CLAUDE.md profile.json statusline-command.sh)
FORGE_LIB_FILES=(ui.sh)

forge_shipped_rules() {
  for f in "$FORGE_SOURCE_DIR/templates/rules/"*.md; do
    [ -f "$f" ] && basename "$f" .md
  done
}

forge_shipped_hooks() {
  for f in "$FORGE_SOURCE_DIR/hooks/"*.sh; do
    [ -f "$f" ] && basename "$f" .sh
  done
}

forge_shipped_scripts() {
  for f in "$FORGE_SOURCE_DIR/scripts/"*.sh; do
    [ -f "$f" ] && basename "$f" .sh
  done
}
