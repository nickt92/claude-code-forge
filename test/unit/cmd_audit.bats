#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-audit.sh — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/cmd-audit.sh"
}

teardown() {
  teardown_sandbox
}

# ── Help ─────────────────────────────────────────────────────

@test "audit --help shows usage" {
  run cmd_audit --help
  assert_success
  assert_output --partial "forge audit"
}

@test "audit -h shows usage" {
  run cmd_audit -h
  assert_success
  assert_output --partial "forge audit"
}

# ── Path Validation ──────────────────────────────────────────

@test "audit fails for nonexistent directory" {
  run cmd_audit /nonexistent/path --json
  assert_failure
  assert_output --partial "not found"
}

@test "audit fails without --json flag" {
  mkdir -p "$TEST_SANDBOX/repo"
  run cmd_audit "$TEST_SANDBOX/repo"
  assert_failure
  assert_output --partial "--json"
}

# ── JSON Output ──────────────────────────────────────────────

@test "audit --json outputs valid JSON for repo with CLAUDE.md" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  cat > "$repo/.claude/CLAUDE.md" <<'EOF'
# Test Project

## Overview
A test project.

## Architecture
Monolithic.

## Tech Stack
| Layer | Technology | Version |
|-------|-----------|---------|
| Runtime | Node.js | 20 |

## Development Setup
npm install && npm start

## Testing
npm test

## Git Workflow
Trunk-based development.

## Deployment
Docker containers.
EOF
  run cmd_audit "$repo" --json
  assert_success
  echo "$output" | jq empty
}

@test "audit JSON has schema_version field" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  local version
  version=$(echo "$output" | jq -r '.schema_version')
  [ "$version" = "1" ]
}

@test "audit JSON has has_claude_md field" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  local has
  has=$(echo "$output" | jq -r '.has_claude_md')
  [ "$has" = "true" ]
}

@test "audit reports missing CLAUDE.md" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo"
  run cmd_audit "$repo" --json
  assert_success
  local has
  has=$(echo "$output" | jq -r '.has_claude_md')
  [ "$has" = "false" ]
}

@test "audit detects missing sections" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  local missing_count
  missing_count=$(echo "$output" | jq '.sections.missing | length')
  [ "$missing_count" -gt 0 ]
}

@test "audit reports findings array" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  echo "$output" | jq -e '.findings | type == "array"'
}

@test "audit findings have required fields" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  local finding_count
  finding_count=$(echo "$output" | jq '.findings | length')
  if [ "$finding_count" -gt 0 ]; then
    echo "$output" | jq -e '.findings[0] | has("severity", "code", "detail", "fixable")'
  fi
}

@test "audit uses current directory when no path given" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  cd "$repo"
  run cmd_audit --json
  assert_success
  echo "$output" | jq empty
}

@test "audit reports sections coverage percentage" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  run cmd_audit "$repo" --json
  assert_success
  local coverage
  coverage=$(echo "$output" | jq '.sections.coverage')
  [ "$coverage" -ge 0 ] && [ "$coverage" -le 100 ]
}

@test "audit detects tech stack from package.json" {
  local repo="$TEST_SANDBOX/repo"
  mkdir -p "$repo/.claude"
  echo "# Project" > "$repo/.claude/CLAUDE.md"
  echo '{"dependencies":{"express":"^4.0.0"}}' > "$repo/package.json"
  run cmd_audit "$repo" --json
  assert_success
  echo "$output" | jq -e '.tech_stack'
}
