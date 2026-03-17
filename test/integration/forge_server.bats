#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Integration tests for forge-server.js REST API
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# These tests start a real server instance and test API endpoints.
# Requires: node, curl

# We use a shared server across all tests via a state file.
# The first test starts it, teardown_file cleans up.

_server_state_dir() { echo "${BATS_SUITE_TMPDIR:-/tmp}/.forge-test-server"; }

_ensure_server() {
  local state_dir
  state_dir="$(_server_state_dir)"

  # Already started?
  if [ -f "$state_dir/port" ]; then
    SERVER_PORT=$(cat "$state_dir/port")
    SERVER_TOKEN=$(cat "$state_dir/token")
    SERVER_PID=$(cat "$state_dir/pid")
    TEST_SANDBOX=$(cat "$state_dir/sandbox")
    export CLAUDE_DIR="$TEST_SANDBOX/.claude"
    export BASE_URL="http://127.0.0.1:${SERVER_PORT}"
    return 0
  fi

  # Create state dir
  mkdir -p "$state_dir"

  # Create sandbox
  TEST_SANDBOX="$(mktemp -d)"
  export HOME="$TEST_SANDBOX"
  export CLAUDE_DIR="$TEST_SANDBOX/.claude"
  mkdir -p "$CLAUDE_DIR"/{rules,hooks,scripts,backups,plans,forge-backup,profiles}

  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # Install a minimal profile
  cat > "$CLAUDE_DIR/profile.json" <<EOF
{
  "schema_version": 1,
  "persona": "senior-engineer",
  "label": "Senior Engineer",
  "description": "Test profile",
  "axes": { "communication": "expert", "autonomy": "high", "workflow": "advanced", "depth": "engineering" },
  "quality": ["core", "engineering"]
}
EOF

  cat > "$CLAUDE_DIR/forge-backup/manifest.json" <<EOF
{
  "manifest_version": 2, "forge_version": "1.2.1", "install_timestamp": "2026-01-01T00:00:00Z",
  "persona": "senior-engineer", "source_dir": "${SCRIPT_DIR}", "plugin_group": "full"
}
EOF

  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{ "hooks": {}, "enabledPlugins": { "test-plugin": true } }
EOF

  # Start server
  FORGE_UI_PORT=0 HOME="$TEST_SANDBOX" CLAUDE_DIR="$CLAUDE_DIR" node "$SCRIPT_DIR/lib/forge-server.js" &
  local pid=$!

  # Wait for port file
  local waited=0
  while [ ! -f "$CLAUDE_DIR/forge-ui.port" ] && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [ ! -f "$CLAUDE_DIR/forge-ui.port" ]; then
    kill "$pid" 2>/dev/null
    return 1
  fi

  SERVER_PORT=$(cat "$CLAUDE_DIR/forge-ui.port")
  SERVER_TOKEN=$(cat "$CLAUDE_DIR/forge-ui.token")
  SERVER_PID=$pid
  BASE_URL="http://127.0.0.1:${SERVER_PORT}"

  # Save state
  echo "$SERVER_PORT" > "$state_dir/port"
  echo "$SERVER_TOKEN" > "$state_dir/token"
  echo "$pid" > "$state_dir/pid"
  echo "$TEST_SANDBOX" > "$state_dir/sandbox"
  echo "$SCRIPT_DIR" > "$state_dir/script_dir"
}

setup() {
  if ! command -v node >/dev/null 2>&1; then
    skip "Node.js not available"
  fi

  load '../helpers/test_helper'
  _ensure_server
}

teardown_file() {
  local state_dir
  state_dir="${BATS_SUITE_TMPDIR:-/tmp}/.forge-test-server"
  if [ -f "$state_dir/pid" ]; then
    local pid
    pid=$(cat "$state_dir/pid")
    kill "$pid" 2>/dev/null
    sleep 0.5
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  fi
  if [ -f "$state_dir/sandbox" ]; then
    rm -rf "$(cat "$state_dir/sandbox")"
  fi
  rm -rf "$state_dir"
}

# Helpers
_api() {
  curl -s -X "$1" "${BASE_URL}$2" "${@:3}"
}
_api_post() {
  curl -s -X POST "${BASE_URL}$1" -H "X-Forge-Token: ${SERVER_TOKEN}" -H "Content-Type: application/json" -d "$2"
}
_api_delete() {
  curl -s -X DELETE "${BASE_URL}$1" -H "X-Forge-Token: ${SERVER_TOKEN}"
}

# ── Health ─────────────────────────────────────────────────────

@test "GET /api/health returns server info" {
  run _api GET /api/health
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"forge_version"'
  assert_output --partial '"node_version"'
  assert_output --partial '"uptime"'
}

# ── Status ─────────────────────────────────────────────────────

@test "GET /api/status returns persona data" {
  run _api GET /api/status
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"persona"'
  assert_output --partial '"senior-engineer"'
}

# ── Personas ───────────────────────────────────────────────────

@test "GET /api/personas returns built-in profiles" {
  run _api GET /api/personas
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"personas"'
  assert_output --partial '"senior-engineer"'
}

@test "GET /api/personas/:name returns single persona" {
  run _api GET /api/personas/senior-engineer
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"axes"'
}

@test "GET /api/personas/:name returns 404 for unknown" {
  run _api GET /api/personas/nonexistent-persona
  assert_output --partial '"ok":false'
  assert_output --partial 'not found'
}

# ── Config ─────────────────────────────────────────────────────

@test "GET /api/config returns object" {
  run _api GET /api/config
  assert_success
  assert_output --partial '"ok":true'
}

# ── Axes ───────────────────────────────────────────────────────

@test "GET /api/axes returns known axis names" {
  run _api GET /api/axes
  assert_success
  assert_output --partial '"communication"'
  assert_output --partial '"autonomy"'
  assert_output --partial '"workflow"'
  assert_output --partial '"depth"'
}

# ── Plugins ────────────────────────────────────────────────────

@test "GET /api/plugins returns groups and installed" {
  run _api GET /api/plugins
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"groups"'
  assert_output --partial '"installed"'
}

# ── Security ───────────────────────────────────────────────────

@test "GET /api/security returns entries array" {
  run _api GET /api/security
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"entries"'
}

# ── Sessions ───────────────────────────────────────────────────

@test "GET /api/sessions returns sessions list" {
  run _api GET /api/sessions
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"sessions"'
}

# ── Token Security ─────────────────────────────────────────────

@test "POST without token returns 403" {
  run curl -s -X POST "${BASE_URL}/api/doctor" -H "Content-Type: application/json"
  assert_success
  assert_output --partial '"ok":false'
  assert_output --partial 'token'
}

@test "POST with wrong token returns 403" {
  run curl -s -X POST "${BASE_URL}/api/doctor" -H "X-Forge-Token: wrong-token" -H "Content-Type: application/json"
  assert_success
  assert_output --partial '"ok":false'
  assert_output --partial 'token'
}

@test "POST with valid token succeeds" {
  run _api_post /api/doctor ''
  assert_success
  assert_output --partial '"ok":true'
}

# ── Content-Type Check ─────────────────────────────────────────

@test "POST with form-urlencoded is rejected" {
  run curl -s -X POST "${BASE_URL}/api/doctor" \
    -H "X-Forge-Token: ${SERVER_TOKEN}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "foo=bar"
  assert_output --partial '"ok":false'
  assert_output --partial 'Form-urlencoded'
}

# ── Build ──────────────────────────────────────────────────────

@test "POST /api/build creates custom profile" {
  run _api_post /api/build '{"name":"test-build","communication":"expert","autonomy":"high","workflow":"advanced","depth":"engineering","quality":["core","engineering"],"default_plugin_group":"full"}'
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"custom-test-build"'
  assert [ -f "$CLAUDE_DIR/profiles/custom-test-build.json" ]
}

@test "POST /api/build rejects invalid name" {
  run _api_post /api/build '{"name":"123bad","communication":"expert","autonomy":"high","workflow":"advanced","depth":"engineering"}'
  assert_output --partial '"ok":false'
  assert_output --partial 'Invalid name'
}

@test "POST /api/build rejects invalid axis value" {
  run _api_post /api/build '{"name":"test2","communication":"invalid","autonomy":"high","workflow":"advanced","depth":"engineering"}'
  assert_output --partial '"ok":false'
  assert_output --partial 'Invalid communication'
}

# ── Delete Persona ─────────────────────────────────────────────

@test "DELETE /api/personas/:name removes custom persona" {
  _api_post /api/build '{"name":"to-delete","communication":"plain","autonomy":"guided","workflow":"simplified","depth":"conceptual"}'
  assert [ -f "$CLAUDE_DIR/profiles/custom-to-delete.json" ]

  run _api_delete /api/personas/custom-to-delete
  assert_success
  assert_output --partial '"ok":true'
  assert_output --partial '"deleted"'
  assert [ ! -f "$CLAUDE_DIR/profiles/custom-to-delete.json" ]
}

@test "DELETE /api/personas/:name rejects built-in" {
  run _api_delete /api/personas/senior-engineer
  assert_output --partial '"ok":false'
  assert_output --partial 'built-in'
}

# ── Invalid JSON ───────────────────────────────────────────────

@test "POST with invalid JSON returns 400" {
  run curl -s -X POST "${BASE_URL}/api/switch" \
    -H "X-Forge-Token: ${SERVER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "not json"
  assert_output --partial '"ok":false'
  assert_output --partial 'Invalid JSON'
}

# ── 404 ────────────────────────────────────────────────────────

@test "unknown API route returns 404" {
  run _api GET /api/nonexistent
  assert_output --partial '"ok":false'
  assert_output --partial 'Not found'
}

@test "non-API route returns 404" {
  run curl -s "${BASE_URL}/random-path"
  assert_output "Not found"
}

# ── SPA ────────────────────────────────────────────────────────

@test "GET / serves index.html" {
  run _api GET /
  assert_success
  assert_output --partial '<!DOCTYPE html>'
  assert_output --partial 'Forge UI'
}

@test "GET / with token param injects token" {
  run curl -s "${BASE_URL}/?token=test123"
  assert_success
  assert_output --partial 'test123'
}

# ── Config Validation ──────────────────────────────────────────

@test "POST /api/config validates key format" {
  run _api_post /api/config '{"key":"bad key!","value":"test"}'
  assert_output --partial '"ok":false'
  assert_output --partial 'Invalid key'
}
