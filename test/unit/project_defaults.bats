#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# .forge/defaults.json — project defaults unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cmd-install.sh"
  PROJECT="$TEST_SANDBOX/project"
  mkdir -p "$PROJECT/.forge"
}

teardown() {
  teardown_sandbox
}

# ── Reading defaults ─────────────────────────────────────────

@test "reads persona from .forge/defaults.json" {
  cat > "$PROJECT/.forge/defaults.json" <<'JSON'
{"persona": "junior-dev", "plugins": "minimal"}
JSON
  cd "$PROJECT"
  _read_project_defaults
  [ "$_DEFAULT_PERSONA" = "junior-dev" ]
  [ "$_DEFAULT_PLUGINS" = "minimal" ]
}

@test "reads all four fields" {
  cat > "$PROJECT/.forge/defaults.json" <<'JSON'
{
  "persona": "senior-engineer",
  "plugins": "full",
  "permissions": "standard",
  "planning_enforcement": "enforce"
}
JSON
  cd "$PROJECT"
  _read_project_defaults
  [ "$_DEFAULT_PERSONA" = "senior-engineer" ]
  [ "$_DEFAULT_PLUGINS" = "full" ]
  [ "$_DEFAULT_PERMISSIONS" = "standard" ]
  [ "$_DEFAULT_PLANNING_ENFORCEMENT" = "enforce" ]
}

@test "missing file is a no-op" {
  cd "$PROJECT"
  rm -rf "$PROJECT/.forge/defaults.json"
  _read_project_defaults
  [ -z "$_DEFAULT_PERSONA" ]
  [ -z "$_DEFAULT_PLUGINS" ]
}

@test "malformed JSON is a no-op" {
  echo "not json {{{" > "$PROJECT/.forge/defaults.json"
  cd "$PROJECT"
  _read_project_defaults
  [ -z "$_DEFAULT_PERSONA" ]
}

@test "partial fields only set what exists" {
  echo '{"plugins": "essential"}' > "$PROJECT/.forge/defaults.json"
  cd "$PROJECT"
  _read_project_defaults
  [ -z "$_DEFAULT_PERSONA" ]
  [ "$_DEFAULT_PLUGINS" = "essential" ]
}

@test "empty JSON object is a no-op" {
  echo '{}' > "$PROJECT/.forge/defaults.json"
  cd "$PROJECT"
  _read_project_defaults
  [ -z "$_DEFAULT_PERSONA" ]
  [ -z "$_DEFAULT_PLUGINS" ]
}

# ── cmd-init persona fallback ────────────────────────────────

@test "cmd_init uses .forge/defaults.json persona when no flag or global profile" {
  cat > "$PROJECT/.forge/defaults.json" <<'JSON'
{"persona": "senior-engineer"}
JSON
  rm -f "$CLAUDE_DIR/profile.json"
  source "$SCRIPT_DIR/lib/assembly.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  run cmd_init --dir "$PROJECT" --skip-docs
  assert_success
  assert_output --partial "Senior Engineer"
}
