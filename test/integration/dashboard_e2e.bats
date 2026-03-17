#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# End-to-end tests for forge dashboard
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
}

teardown() {
  teardown_sandbox
}

# ── Config → Dashboard Pipeline ──────────────────────────────

@test "config set + dashboard generates HTML with repo data" {
  # Set up global config
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# Global CLAUDE.md with lots of content" > "$CLAUDE_DIR/CLAUDE.md"
  for i in $(seq 1 60); do echo "Line $i" >> "$CLAUDE_DIR/CLAUDE.md"; done
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/command-guard.sh", "timeout": 5}]}]}, "enabledPlugins": {"p1": true}}
EOF

  # Create some repos
  local scan_dir="$TEST_SANDBOX/repos"
  mkdir -p "$scan_dir/project-alpha/.claude/rules"
  echo "# Alpha config" > "$scan_dir/project-alpha/.claude/CLAUDE.md"
  echo "# Rule" > "$scan_dir/project-alpha/.claude/rules/test.md"
  touch "$scan_dir/project-alpha/PROJECT.md"
  touch "$scan_dir/project-alpha/ROADMAP.md"

  mkdir -p "$scan_dir/project-beta/.claude"

  # Configure scan path
  source "$SCRIPT_DIR/lib/cmd-config.sh"
  _config_set "dashboard.scan_path" "$scan_dir"

  # Generate dashboard (no run — avoid clobbering $output)
  local out_file="$TEST_SANDBOX/test-dashboard.html"
  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  cmd_dashboard --output "$out_file"

  # Verify HTML was created
  assert [ -f "$out_file" ]

  # Verify it contains expected content
  local content
  content=$(cat "$out_file")
  echo "$content" | grep -q "<!DOCTYPE html>"
  echo "$content" | grep -q "const DATA ="
  echo "$content" | grep -q "Forge Dashboard"

  # Verify data includes repos
  echo "$content" | grep -q "project-alpha"
  echo "$content" | grep -q "project-beta"
}

@test "dashboard works without scan path configured" {
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {}, "enabledPlugins": {}}
EOF

  local out_file="$TEST_SANDBOX/test-dashboard.html"
  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  run cmd_dashboard --output "$out_file"
  assert_success
  assert [ -f "$out_file" ]
  assert_output --partial "No scan path configured"
}

@test "dashboard --help shows usage" {
  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  run cmd_dashboard --help
  assert_success
  assert_output --partial "forge dashboard"
  assert_output --partial "--open"
  assert_output --partial "--output"
}

@test "dashboard default output goes to ~/.claude/dashboard/index.html" {
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {}, "enabledPlugins": {}}
EOF

  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  cmd_dashboard
  assert [ -f "$CLAUDE_DIR/dashboard/index.html" ]
}

@test "dashboard rejects unknown flags" {
  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  run cmd_dashboard --bogus
  assert_failure
  assert_output --partial "Unknown option"
}

# ── Scoring in Pipeline ──────────────────────────────────────

@test "dashboard scores repos correctly in full pipeline" {
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {}, "enabledPlugins": {}}
EOF

  local scan_dir="$TEST_SANDBOX/repos"

  # Well-configured repo
  mkdir -p "$scan_dir/good-repo/.claude/rules"
  echo "# Config" > "$scan_dir/good-repo/.claude/CLAUDE.md"
  for i in $(seq 1 20); do echo "Line $i" >> "$scan_dir/good-repo/.claude/CLAUDE.md"; done
  echo "# Rule 1" > "$scan_dir/good-repo/.claude/rules/r1.md"
  echo "# Rule 2" > "$scan_dir/good-repo/.claude/rules/r2.md"
  echo "# Rule 3" > "$scan_dir/good-repo/.claude/rules/r3.md"
  touch "$scan_dir/good-repo/PROJECT.md"
  touch "$scan_dir/good-repo/REQUIREMENTS.md"
  touch "$scan_dir/good-repo/ROADMAP.md"

  # Minimal repo
  mkdir -p "$scan_dir/bare-repo/.claude"

  source "$SCRIPT_DIR/lib/cmd-config.sh"
  _config_set "dashboard.scan_path" "$scan_dir"

  local out_file="$TEST_SANDBOX/scored.html"
  source "$SCRIPT_DIR/lib/cmd-dashboard.sh"
  cmd_dashboard --output "$out_file"

  # Extract JSON from HTML: find "const DATA = " and extract to matching ";""
  local json
  json=$(sed -n 's/^<script>const DATA = \(.*\);<\/script>$/\1/p' "$out_file")

  # Good repo should have high score
  local good_score
  good_score=$(echo "$json" | jq '[.repos[] | select(.name == "good-repo")][0].score.total')
  [ "$good_score" -ge 70 ]

  # Bare repo should have low score
  local bare_score
  bare_score=$(echo "$json" | jq '[.repos[] | select(.name == "bare-repo")][0].score.total')
  [ "$bare_score" -lt 50 ]
}

# ── Config command via forge dispatcher ──────────────────────

@test "forge dispatches to config command" {
  run "$SCRIPT_DIR/forge" config --help
  assert_success
  assert_output --partial "forge config"
}

@test "forge dispatches to dashboard command" {
  create_test_profile "senior-engineer"
  create_test_manifest_v2 "senior-engineer"
  echo "# CLAUDE.md" > "$CLAUDE_DIR/CLAUDE.md"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{"hooks": {}, "enabledPlugins": {}}
EOF

  local out_file="$TEST_SANDBOX/dispatch-test.html"
  run "$SCRIPT_DIR/forge" dashboard --output "$out_file"
  assert_success
  assert [ -f "$out_file" ]
}
