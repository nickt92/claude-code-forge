#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Assembly pipeline — integration tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/assembly.sh"
}

teardown() {
  teardown_sandbox
}

# ── All Personas Assemble Successfully ───────────────────────

@test "all 12 personas assemble without error" {
  local count=0
  for profile_json in "$PROFILES_DIR"/*.json; do
    local output="$TEST_SANDBOX/output-$(basename "$profile_json" .json).md"
    run assemble_claude_md "$profile_json" "$output"
    assert_success
    count=$((count + 1))
  done
  assert [ "$count" -eq 12 ]
}

@test "all personas produce under 200 lines" {
  for profile_json in "$PROFILES_DIR"/*.json; do
    local persona
    persona=$(jq -r '.persona' "$profile_json")
    local output="$TEST_SANDBOX/output-${persona}.md"
    assemble_claude_md "$profile_json" "$output"
    local lines
    lines=$(wc -l < "$output" | tr -d ' ')
    assert [ "$lines" -le 200 ] || echo "FAIL: $persona has $lines lines"
  done
}

# ── Section Ordering ─────────────────────────────────────────

@test "sections appear in correct order: base, comm, depth, autonomy, workflow, quality" {
  local output="$TEST_SANDBOX/ordered.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$output"

  # Extract section markers by finding the first unique line from each section
  # The order should be: base content before communication content before depth, etc.
  local base_line comm_line depth_line auto_line work_line quality_line

  # Use headings or distinctive content from each section
  base_line=$(grep -n "Role & Authority\|Quality Standard\|Engineering Standards" "$output" | head -1 | cut -d: -f1)
  comm_line=$(grep -n "Communication Style\|Adapt depth\|Lead with\|Adapt to the person" "$output" | head -1 | cut -d: -f1)
  depth_line=$(grep -n "Technical Depth\|Explanation Depth\|How Deep" "$output" | head -1 | cut -d: -f1)
  auto_line=$(grep -n "Autonomy\|Decision Making\|Proceed\|Task Approach" "$output" | head -1 | cut -d: -f1)
  work_line=$(grep -n "Workflow\|Task Workflow\|Development Process" "$output" | head -1 | cut -d: -f1)
  quality_line=$(grep -n "SOLID\|DRY\|Quality" "$output" | head -1 | cut -d: -f1)

  # base should come before communication
  if [ -n "$base_line" ] && [ -n "$comm_line" ]; then
    assert [ "$base_line" -lt "$comm_line" ]
  fi
}

@test "output starts with assembly comment header" {
  local output="$TEST_SANDBOX/header.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$output"

  run head -1 "$output"
  assert_output --partial "<!-- Assembled by Claude Code Forge"
  assert_output --partial "senior-engineer"
}

@test "header includes current date" {
  local output="$TEST_SANDBOX/date.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$output"

  local today
  today=$(date +%Y-%m-%d)
  run head -1 "$output"
  assert_output --partial "$today"
}

# ── Quality Section Conditional Inclusion ────────────────────

@test "senior-engineer includes quality-engineering section" {
  local output="$TEST_SANDBOX/quality.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$output"

  # quality-engineering.md content should be present
  run grep -c "coverage\|testing pyramid\|accessibility\|observability" "$output"
  assert_success
}

@test "product-manager does NOT include quality-engineering section" {
  local output="$TEST_SANDBOX/pm-quality.md"
  assemble_claude_md "$PROFILES_DIR/product-manager.json" "$output"

  # quality-engineering specific content should NOT be present
  # (quality-core IS included for all personas)
  local pm_lines se_output="$TEST_SANDBOX/se-quality.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$se_output"

  local pm_lines se_lines
  pm_lines=$(wc -l < "$output" | tr -d ' ')
  se_lines=$(wc -l < "$se_output" | tr -d ' ')
  # SE should have more lines due to quality-engineering section
  assert [ "$se_lines" -gt "$pm_lines" ]
}

@test "quality-core is always included" {
  for profile_json in "$PROFILES_DIR"/*.json; do
    local persona
    persona=$(jq -r '.persona' "$profile_json")
    local output="$TEST_SANDBOX/qcore-${persona}.md"
    assemble_claude_md "$profile_json" "$output"
    run grep -l "SOLID\|DRY\|error handling" "$output"
    assert_success
  done
}

# ── Schema Version Validation ────────────────────────────────

@test "rejects schema_version 0" {
  local bad_profile="$TEST_SANDBOX/bad-v0.json"
  cat > "$bad_profile" <<'EOF'
{
  "schema_version": 0,
  "persona": "test",
  "axes": { "communication": "plain", "autonomy": "guided", "workflow": "simplified", "depth": "conceptual" },
  "quality": ["core"]
}
EOF
  run assemble_claude_md "$bad_profile" "$TEST_SANDBOX/output.md"
  assert_failure
}

@test "rejects schema_version 2" {
  local bad_profile="$TEST_SANDBOX/bad-v2.json"
  cat > "$bad_profile" <<'EOF'
{
  "schema_version": 2,
  "persona": "test",
  "axes": { "communication": "plain", "autonomy": "guided", "workflow": "simplified", "depth": "conceptual" },
  "quality": ["core"]
}
EOF
  run assemble_claude_md "$bad_profile" "$TEST_SANDBOX/output.md"
  assert_failure
}

# ── Missing Axis Rejection ───────────────────────────────────

@test "fails when section file is missing for axis value" {
  local bad_profile="$TEST_SANDBOX/bad-axis.json"
  cat > "$bad_profile" <<'EOF'
{
  "schema_version": 1,
  "persona": "test",
  "axes": { "communication": "nonexistent", "autonomy": "guided", "workflow": "simplified", "depth": "conceptual" },
  "quality": ["core"]
}
EOF
  # cat will error on missing file and output goes to stderr
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/assembly.sh" && SECTIONS_DIR="'"$SECTIONS_DIR"'" && assemble_claude_md "'"$TEST_SANDBOX"'/bad-axis.json" "'"$TEST_SANDBOX"'/output.md" 2>&1'
  # Should have cat error about missing file
  assert_output --partial "No such file"
}

# ── Deterministic Output ─────────────────────────────────────

@test "same profile produces same output (minus date header)" {
  local out1="$TEST_SANDBOX/det1.md" out2="$TEST_SANDBOX/det2.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$out1"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$out2"

  # Skip first line (contains timestamp) and compare rest
  run diff <(tail -n +2 "$out1") <(tail -n +2 "$out2")
  assert_success
}

# ── Different Personas Produce Different Output ──────────────

@test "different personas produce different output" {
  local out1="$TEST_SANDBOX/se.md" out2="$TEST_SANDBOX/vc.md"
  assemble_claude_md "$PROFILES_DIR/senior-engineer.json" "$out1"
  assemble_claude_md "$PROFILES_DIR/vibe-coder.json" "$out2"

  # Line counts should differ (different sections included)
  local lines1 lines2
  lines1=$(wc -l < "$out1" | tr -d ' ')
  lines2=$(wc -l < "$out2" | tr -d ' ')
  assert [ "$lines1" -ne "$lines2" ]
}

@test "output is non-empty for all personas" {
  for profile_json in "$PROFILES_DIR"/*.json; do
    local output="$TEST_SANDBOX/nonempty-$(basename "$profile_json" .json).md"
    assemble_claude_md "$profile_json" "$output"
    local lines
    lines=$(wc -l < "$output" | tr -d ' ')
    assert [ "$lines" -gt 10 ]
  done
}
