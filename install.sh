#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Claude Code Forge — Installer (thin wrapper)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Delegates to `forge install`. This file exists for backward
# compatibility — `./install.sh` still works as before.
#
# Usage:
#   chmod +x install.sh && ./install.sh
#   ./install.sh --profile senior-engineer
#   ./install.sh --reconfigure
#   ./install.sh --uninstall
#   ./install.sh --quiet --profile senior-engineer
#   ./install.sh --help

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/forge" install "$@"
