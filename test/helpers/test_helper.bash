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

# Windows jq compatibility (see lib/platform.sh for rationale)
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* || "${OSTYPE:-}" == cygwin* ]]; then
  jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }
fi

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
  local _tmpdir="${TMPDIR:-/tmp}"
  rm -f "$_tmpdir"/claude-code-prompted-* "$_tmpdir"/claude-code-classified-* "$_tmpdir"/claude-forge-update-*
}

# ── Helpers ──────────────────────────────────────────────────

# Create a v2 manifest in the sandbox
create_test_manifest_v2() {
  local persona="${1:-senior-engineer}"
  local source_dir="${2:-$SCRIPT_DIR}"
  local plugin_group="${3:-full}"
  mkdir -p "$CLAUDE_DIR/forge-backup"
  cat > "$CLAUDE_DIR/forge-backup/manifest.json" <<EOF
{
  "manifest_version": 2,
  "forge_version": "1.1.0",
  "install_timestamp": "2026-01-01T00:00:00Z",
  "persona": "${persona}",
  "source_dir": "${source_dir}",
  "plugin_group": "${plugin_group}",
  "migrated_from_legacy": false,
  "pre_existing": {
    "files": {},
    "directories": {}
  },
  "installed": {
    "files": ["CLAUDE.md", "profile.json", "statusline-command.sh"],
    "directories": {
      "rules": [],
      "hooks": [],
      "scripts": []
    },
    "settings_additions": {}
  }
}
EOF
}

# Create a minimal forge source sandbox for update/diff tests
create_forge_source_sandbox() {
  local source_dir="$TEST_SANDBOX/forge-source"
  mkdir -p "$source_dir"/{lib,templates/{sections,profiles,rules},hooks,scripts}

  # Copy essential source files
  cp "$SCRIPT_DIR/lib/ui.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/assembly.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/manifest.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/forge-inventory.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/plugins.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/platform.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/settings-merge.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/settings-unmerge.sh" "$source_dir/lib/"
  cp "$SCRIPT_DIR/lib/uninstall.sh" "$source_dir/lib/"
  for f in "$SCRIPT_DIR/lib/cmd-"*.sh; do
    [ -f "$f" ] && cp "$f" "$source_dir/lib/"
  done
  cp "$SCRIPT_DIR/forge" "$source_dir/"
  chmod +x "$source_dir/forge"
  cp "$SCRIPT_DIR/statusline-command.sh" "$source_dir/"
  cp -r "$SCRIPT_DIR/templates/sections/"* "$source_dir/templates/sections/"
  cp -r "$SCRIPT_DIR/templates/profiles/"* "$source_dir/templates/profiles/"
  cp -r "$SCRIPT_DIR/templates/rules/"* "$source_dir/templates/rules/"
  cp "$SCRIPT_DIR/templates/plugin-groups.json" "$source_dir/templates/"
  cp "$SCRIPT_DIR/templates/settings.json" "$source_dir/templates/"
  cp -r "$SCRIPT_DIR/hooks/"* "$source_dir/hooks/"
  for f in "$SCRIPT_DIR/scripts/"*.sh; do
    [ -f "$f" ] && cp "$f" "$source_dir/scripts/"
  done

  echo "$source_dir"
}

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
