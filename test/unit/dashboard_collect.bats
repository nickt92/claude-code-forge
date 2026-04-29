#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests for dashboard data collection
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/platform.sh"
  source "$SCRIPT_DIR/lib/dashboard/collect-global.sh"
  source "$SCRIPT_DIR/lib/dashboard/collect-repos.sh"
}

teardown() {
  teardown_sandbox
}

# ── Global: Persona Collection ───────────────────────────────

@test "collect persona returns unknown when no profile.json" {
  run _collect_persona
  assert_success
  local persona
  persona=$(echo "$output" | jq -r '.persona')
  assert_equal "$persona" "unknown"
}

@test "collect persona reads profile.json correctly" {
  create_test_profile "senior-engineer"
  run _collect_persona
  assert_success
  local persona
  persona=$(echo "$output" | jq -r '.persona')
  assert_equal "$persona" "senior-engineer"
  local label
  label=$(echo "$output" | jq -r '.label')
  assert_equal "$label" "Test Profile"
}

@test "collect persona includes axes" {
  create_test_profile "cto-architect" "high" "advanced" "expert" "architecture"
  run _collect_persona
  assert_success
  local autonomy
  autonomy=$(echo "$output" | jq -r '.axes.autonomy')
  assert_equal "$autonomy" "high"
}

# ── Global: Hook Collection ──────────────────────────────────

@test "collect hooks returns empty array when no settings.json" {
  run _collect_hooks
  assert_success
  assert_output "[]"
}

@test "collect hooks extracts hook entries from settings.json" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/command-guard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF
  run _collect_hooks
  assert_success
  local count
  count=$(echo "$output" | jq 'length')
  assert_equal "$count" "1"
  local event
  event=$(echo "$output" | jq -r '.[0].event')
  assert_equal "$event" "PreToolUse"
  local name
  name=$(echo "$output" | jq -r '.[0].name')
  assert_equal "$name" "command-guard"
}

# ── Global: Plugin Collection ────────────────────────────────

@test "collect plugins returns unknown group without manifest" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"enabledPlugins": {"plugin1": true}}
EOF
  run _collect_plugins
  assert_success
  local group
  group=$(echo "$output" | jq -r '.group')
  assert_equal "$group" "unknown"
  local count
  count=$(echo "$output" | jq -r '.count')
  assert_equal "$count" "1"
}

@test "collect plugins reads group from manifest" {
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "standard"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"enabledPlugins": {"p1": true, "p2": true, "p3": true}}
EOF
  run _collect_plugins
  assert_success
  local group
  group=$(echo "$output" | jq -r '.group')
  assert_equal "$group" "standard"
  local count
  count=$(echo "$output" | jq -r '.count')
  assert_equal "$count" "3"
}

# ── Global: Rules Collection ─────────────────────────────────

@test "collect rules returns zero count when no rules dir" {
  rm -rf "$CLAUDE_DIR/rules"
  run _collect_rules
  assert_success
  local count
  count=$(echo "$output" | jq -r '.count')
  assert_equal "$count" "0"
}

@test "collect rules counts rule files" {
  echo "# Rule 1" > "$CLAUDE_DIR/rules/scope-discipline.md"
  echo "# Rule 2" > "$CLAUDE_DIR/rules/agent-orchestration.md"
  run _collect_rules
  assert_success
  local count
  count=$(echo "$output" | jq -r '.count')
  assert_equal "$count" "2"
}

# ── Global: CLAUDE.md Status ─────────────────────────────────

@test "collect claude_md status when missing" {
  run _collect_claude_md_status
  assert_success
  local exists
  exists=$(echo "$output" | jq -r '.exists')
  assert_equal "$exists" "false"
}

@test "collect claude_md status when present" {
  printf '%s\n' "# Claude Config" "Line 2" "Line 3" > "$CLAUDE_DIR/CLAUDE.md"
  run _collect_claude_md_status
  assert_success
  local exists
  exists=$(echo "$output" | jq -r '.exists')
  assert_equal "$exists" "true"
  local lines
  lines=$(echo "$output" | jq -r '.lines')
  assert_equal "$lines" "3"
}

# ── Global: Full Collection ──────────────────────────────────

@test "collect_global_config produces valid JSON with all fields" {
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  echo "# Rule" > "$CLAUDE_DIR/rules/test-rule.md"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {}, "enabledPlugins": {"p1": true}}
EOF

  run collect_global_config
  assert_success
  # Verify it's valid JSON with expected top-level keys
  echo "$output" | jq -e '.persona' >/dev/null
  echo "$output" | jq -e '.hooks' >/dev/null
  echo "$output" | jq -e '.plugins' >/dev/null
  echo "$output" | jq -e '.rules' >/dev/null
  echo "$output" | jq -e '.install' >/dev/null
  echo "$output" | jq -e '.claude_md' >/dev/null
}

# ── Repo: Discovery ─────────────────────────────────────────

@test "discover repos finds .claude directories" {
  local scan_dir="$TEST_SANDBOX/repos"
  mkdir -p "$scan_dir/project-a/.claude"
  mkdir -p "$scan_dir/project-b/.claude"

  run _discover_repos "$scan_dir" 3
  assert_success
  assert_output --partial "project-a"
  assert_output --partial "project-b"
}

@test "discover repos returns nothing for empty directory" {
  local scan_dir="$TEST_SANDBOX/empty"
  mkdir -p "$scan_dir"
  run _discover_repos "$scan_dir" 3
  assert_success
  assert_output ""
}

@test "discover repos returns nothing for nonexistent path" {
  run _discover_repos "/nonexistent/path" 3
  assert_success
  assert_output ""
}

# ── Repo: Data Collection ───────────────────────────────────

@test "collect repo data includes CLAUDE.md status" {
  local repo="$TEST_SANDBOX/repos/my-project"
  mkdir -p "$repo/.claude"
  echo "# Project config" > "$repo/.claude/CLAUDE.md"

  run _collect_repo_data "$repo"
  assert_success
  local has_claude_md
  has_claude_md=$(echo "$output" | jq -r '.claude_md.exists')
  assert_equal "$has_claude_md" "true"
}

@test "collect repo data includes document chain status" {
  local repo="$TEST_SANDBOX/repos/my-project"
  mkdir -p "$repo/.claude"
  touch "$repo/PROJECT.md"
  touch "$repo/ROADMAP.md"

  run _collect_repo_data "$repo"
  assert_success
  local has_project
  has_project=$(echo "$output" | jq -r '.doc_chain.project_md')
  assert_equal "$has_project" "true"
  local has_roadmap
  has_roadmap=$(echo "$output" | jq -r '.doc_chain.roadmap_md')
  assert_equal "$has_roadmap" "true"
  local has_requirements
  has_requirements=$(echo "$output" | jq -r '.doc_chain.requirements_md')
  assert_equal "$has_requirements" "false"
}

@test "collect repo data includes rules count" {
  local repo="$TEST_SANDBOX/repos/my-project"
  mkdir -p "$repo/.claude/rules"
  echo "# Rule" > "$repo/.claude/rules/test.md"
  echo "# Rule" > "$repo/.claude/rules/other.md"

  run _collect_repo_data "$repo"
  assert_success
  local count
  count=$(echo "$output" | jq -r '.rules.count')
  assert_equal "$count" "2"
}

@test "collect repo data detects docchain dismissal" {
  local repo="$TEST_SANDBOX/repos/my-project"
  mkdir -p "$repo/.claude"
  touch "$repo/.claude/.docchain-skip"

  run _collect_repo_data "$repo"
  assert_success
  local dismissed
  dismissed=$(echo "$output" | jq -r '.doc_chain.dismissed')
  assert_equal "$dismissed" "true"
}

# ── Repo: Full Collection ───────────────────────────────────

@test "collect_repos returns JSON array" {
  local scan_dir="$TEST_SANDBOX/repos"
  mkdir -p "$scan_dir/project-a/.claude"
  mkdir -p "$scan_dir/project-b/.claude"

  run collect_repos "$scan_dir" 3
  assert_success
  local count
  count=$(echo "$output" | jq 'length')
  assert_equal "$count" "2"
}

@test "collect_repos returns empty array for no scan path" {
  run collect_repos "" 3
  assert_success
  assert_output "[]"
}

@test "collect_repos returns empty array for nonexistent path" {
  run collect_repos "/nonexistent" 3
  assert_success
  assert_output "[]"
}
