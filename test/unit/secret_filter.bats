#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Secret Filter Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/secret-filter.sh"
  # Ensure CLAUDE_DIR points to sandbox for log file
  export CLAUDE_DIR="$TEST_SANDBOX/.claude"
}

teardown() {
  teardown_sandbox
}

# Helper: run hook with tool response content
run_hook() {
  local response="$1"
  local tool="${2:-Bash}"
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  jq -n --arg r "$response" --arg t "$tool" '{"tool_response":$r,"tool_name":$t}' > "$tmpfile"
  bash "$HOOK" < "$tmpfile"
}

# ── AWS Keys ──────────────────────────────────────────────────

@test "detects AWS access key" {
  run run_hook 'export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE'
  assert_success
  assert_output --partial "SECURITY WARNING"
  assert_output --partial "AWS access key"
}

@test "no false positive on short AKIA prefix" {
  run run_hook 'AKIAI is not a key'
  assert_success
  assert_output ''
}

# ── GitHub Tokens ─────────────────────────────────────────────

@test "detects GitHub personal access token (ghp_)" {
  run run_hook 'token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn'
  assert_success
  assert_output --partial "GitHub token"
}

@test "detects GitHub server token (ghs_)" {
  run run_hook 'GHS_TOKEN=ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn'
  assert_success
  assert_output --partial "GitHub token"
}

@test "detects github_pat_ token" {
  run run_hook 'github_pat_ABC123DEF456_something'
  assert_success
  assert_output --partial "GitHub PAT"
}

# ── API Keys (sk-) ────────────────────────────────────────────

@test "detects OpenAI/Anthropic API key" {
  run run_hook 'OPENAI_API_KEY=sk-proj-ABCDEFGHIJKLMNOPQRSTUVWXYZab'
  assert_success
  assert_output --partial "API key (sk-)"
}

@test "no false positive on short sk- string" {
  run run_hook 'sk-short'
  assert_success
  assert_output ''
}

# ── Slack Tokens ──────────────────────────────────────────────

@test "detects Slack bot token" {
  run run_hook 'SLACK_TOKEN=xoxb-123456-789012-abcdef'
  assert_success
  assert_output --partial "Slack token"
}

@test "detects Slack user token" {
  run run_hook 'token=xoxp-user-token-here'
  assert_success
  assert_output --partial "Slack token"
}

# ── NPM Tokens ───────────────────────────────────────────────

@test "detects NPM token" {
  run run_hook 'NPM_TOKEN=npm_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn'
  assert_success
  assert_output --partial "NPM token"
}

# ── Bearer Tokens ─────────────────────────────────────────────

@test "detects Bearer token" {
  run run_hook 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkw'
  assert_success
  assert_output --partial "Bearer token"
}

@test "no false positive on short Bearer" {
  run run_hook 'Bearer abc'
  assert_success
  assert_output ''
}

# ── Private Keys ──────────────────────────────────────────────

@test "detects RSA private key" {
  run run_hook '-----BEGIN RSA PRIVATE KEY-----'
  assert_success
  assert_output --partial "private key"
}

@test "detects EC private key" {
  run run_hook '-----BEGIN EC PRIVATE KEY-----'
  assert_success
  assert_output --partial "private key"
}

# ── Generic Env Secrets ───────────────────────────────────────

@test "detects API_KEY env assignment" {
  run run_hook 'API_KEY=abcdefghijklmnop1234'
  assert_success
  assert_output --partial "env secret"
}

@test "detects DB_PASSWORD env assignment" {
  run run_hook 'DB_PASSWORD=mysupersecretpassword123'
  assert_success
  assert_output --partial "env secret"
}

@test "detects AUTH_TOKEN env assignment" {
  run run_hook 'AUTH_TOKEN=averylongtoken1234567890'
  assert_success
  assert_output --partial "env secret"
}

@test "no false positive on short env values" {
  run run_hook 'KEY=short'
  assert_success
  assert_output ''
}

# ── No Secret (Clean Passthrough) ─────────────────────────────

@test "passes clean output silently" {
  run run_hook 'total 32\ndrwxr-xr-x 4 user staff 128 Jan 1 12:00 src/'
  assert_success
  assert_output ''
}

@test "passes normal code output silently" {
  run run_hook 'function hello() { console.log("hello world"); }'
  assert_success
  assert_output ''
}

# ── Output Format ─────────────────────────────────────────────

@test "output is valid JSON on detection" {
  local output
  output=$(echo '{"tool_response":"AKIAIOSFODNN7EXAMPLE1","tool_name":"Bash"}' | bash "$HOOK")
  run jq -e '.' <<< "$output"
  assert_success
}

@test "includes PostToolUse event name" {
  run run_hook 'AKIAIOSFODNN7EXAMPLE1'
  assert_success
  assert_output --partial "PostToolUse"
}

@test "includes REDACTED instruction" {
  run run_hook 'AKIAIOSFODNN7EXAMPLE1'
  assert_success
  assert_output --partial "REDACTED"
}

# ── Logging ───────────────────────────────────────────────────

@test "logs detection to security.log" {
  run_hook 'AKIAIOSFODNN7EXAMPLE1'
  assert [ -f "$CLAUDE_DIR/security.log" ]
  run cat "$CLAUDE_DIR/security.log"
  assert_output --partial "SECRET_DETECTED"
  assert_output --partial "AWS access key"
}

@test "logs tool name in security.log" {
  run_hook 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn' "Read"
  run cat "$CLAUDE_DIR/security.log"
  assert_output --partial "tool=Read"
}

# ── Edge Cases ────────────────────────────────────────────────

@test "handles empty tool_response" {
  run bash -c 'echo "{\"tool_response\":\"\",\"tool_name\":\"Bash\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

@test "handles missing tool_response" {
  run bash -c 'echo "{\"tool_name\":\"Bash\"}" | bash "$0"' "$HOOK"
  assert_success
  assert_output ''
}

@test "detects multiple secret types in one response" {
  run run_hook 'AKIAIOSFODNN7EXAMPLE1 and xoxb-token-here'
  assert_success
  assert_output --partial "AWS access key"
  assert_output --partial "Slack token"
}
