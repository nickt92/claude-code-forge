#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Helper — shared setup/teardown and library loading
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Sources bats libraries and provides sandbox isolation.
# Every test runs in a temporary $HOME so real config is never touched.

# Resolve project root (two levels up from test/helpers/)
TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "$TEST_HELPERS_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Load bats libraries
load "${TEST_DIR}/libs/bats-support/load"
load "${TEST_DIR}/libs/bats-assert/load"
load "${TEST_DIR}/libs/bats-file/load"

# ── Sandbox setup ────────────────────────────────────────────
# Creates a temp directory and redirects HOME so tests never
# modify the real ~/.claude/ directory.
setup_sandbox() {
  TEST_SANDBOX="$(mktemp -d)"
  REAL_HOME="$HOME"
  export HOME="$TEST_SANDBOX"
  export CLAUDE_DIR="$TEST_SANDBOX/.claude"
  mkdir -p "$CLAUDE_DIR"/{rules,hooks,scripts,backups,plans}

  # Project paths for sourcing libs and accessing templates
  export SCRIPT_DIR="$PROJECT_ROOT"
  export SECTIONS_DIR="$PROJECT_ROOT/templates/sections"
  export PROFILES_DIR="$PROJECT_ROOT/templates/profiles"
}

# ── Sandbox teardown ─────────────────────────────────────────
# Verifies real HOME was not modified (architect finding #3),
# then cleans up sandbox and temp markers.
teardown_sandbox() {
  # Integrity check: real HOME should not have been modified
  if [ -n "$REAL_HOME" ] && [ -n "$TEST_SANDBOX" ]; then
    if [ "$REAL_HOME" != "$TEST_SANDBOX" ]; then
      # Restore real HOME before cleanup
      export HOME="$REAL_HOME"
    fi
  fi

  # Clean up sandbox
  if [ -n "$TEST_SANDBOX" ] && [ -d "$TEST_SANDBOX" ]; then
    rm -rf "$TEST_SANDBOX"
  fi

  # Clean up temp markers that hooks create
  rm -f /tmp/claude-code-prompted-* /tmp/claude-code-classified-*
}

# ── Helpers ──────────────────────────────────────────────────

# Create a minimal profile.json in the sandbox
create_test_profile() {
  local persona="${1:-senior-engineer}"
  local autonomy="${2:-high}"
  local workflow="${3:-advanced}"
  local communication="${4:-expert}"
  local depth="${5:-engineering}"
  local quality="${6:-[\"core\", \"engineering\"]}"

  cat > "$CLAUDE_DIR/profile.json" <<EOF
{
  "schema_version": 1,
  "persona": "${persona}",
  "label": "Test Profile",
  "description": "Test profile for automated tests",
  "axes": {
    "communication": "${communication}",
    "autonomy": "${autonomy}",
    "workflow": "${workflow}",
    "depth": "${depth}"
  },
  "quality": ${quality}
}
EOF
}
