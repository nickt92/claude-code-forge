#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests for dashboard scoring engine
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/dashboard/score.sh"
}

teardown() {
  teardown_sandbox
}

# ── Letter Grade ─────────────────────────────────────────────

@test "score_to_grade returns A for 90+" {
  run score_to_grade 90
  assert_output "A"
  run score_to_grade 100
  assert_output "A"
}

@test "score_to_grade returns B for 80-89" {
  run score_to_grade 80
  assert_output "B"
  run score_to_grade 89
  assert_output "B"
}

@test "score_to_grade returns C for 70-79" {
  run score_to_grade 70
  assert_output "C"
}

@test "score_to_grade returns D for 60-69" {
  run score_to_grade 60
  assert_output "D"
}

@test "score_to_grade returns F for below 60" {
  run score_to_grade 59
  assert_output "F"
  run score_to_grade 0
  assert_output "F"
}

# ── Config Completeness ─────────────────────────────────────

@test "config completeness scores 0 when nothing exists" {
  local json='{"claude_md":{"exists":false,"lines":0},"persona":{"persona":"unknown","axes":{}}}'
  run _score_config_completeness "$json"
  assert_output "0"
}

@test "config completeness scores 100 for full setup" {
  local json='{"claude_md":{"exists":true,"lines":200},"persona":{"persona":"senior-engineer","axes":{"a":"1","b":"2","c":"3","d":"4"}}}'
  run _score_config_completeness "$json"
  assert_output "100"
}

@test "config completeness gives 40 for CLAUDE.md existing only" {
  local json='{"claude_md":{"exists":true,"lines":10},"persona":{"persona":"unknown","axes":{}}}'
  run _score_config_completeness "$json"
  assert_output "40"
}

# ── Rule Coverage ────────────────────────────────────────────

@test "rule coverage scores 100 for 5+ rules" {
  local json='{"rules":{"count":7}}'
  run _score_rule_coverage "$json"
  assert_output "100"
}

@test "rule coverage scores 0 for no rules" {
  local json='{"rules":{"count":0}}'
  run _score_rule_coverage "$json"
  assert_output "0"
}

@test "rule coverage scores proportionally for partial" {
  local json='{"rules":{"count":3}}'
  run _score_rule_coverage "$json"
  assert_output "60"
}

# ── Hook Coverage ────────────────────────────────────────────

@test "hook coverage scores 100 for 6+ hooks" {
  local json='{"hooks":[1,2,3,4,5,6]}'
  run _score_hook_coverage "$json"
  assert_output "100"
}

@test "hook coverage scores 0 for no hooks" {
  local json='{"hooks":[]}'
  run _score_hook_coverage "$json"
  assert_output "0"
}

# ── Plugin Alignment ─────────────────────────────────────────

@test "plugin alignment scores 100 for full group with all plugins" {
  local json='{"plugins":{"group":"full","count":18}}'
  run _score_plugin_alignment "$json"
  assert_output "100"
}

@test "plugin alignment scores proportionally for partial" {
  local json='{"plugins":{"group":"full","count":9}}'
  run _score_plugin_alignment "$json"
  assert_output "50"
}

# ── Global Composite Score ───────────────────────────────────

@test "score_global produces valid JSON with all dimensions" {
  local json='{
    "claude_md":{"exists":true,"lines":200},
    "persona":{"persona":"senior-engineer","axes":{"a":"1","b":"2","c":"3","d":"4"}},
    "rules":{"count":7},
    "hooks":[1,2,3,4,5,6,7],
    "plugins":{"group":"full","count":18},
    "install":{"install_timestamp":"2026-03-17T00:00:00Z"}
  }'
  run score_global "$json"
  assert_success
  # Valid JSON
  echo "$output" | jq -e '.' >/dev/null
  # Has total and grade
  echo "$output" | jq -e '.total' >/dev/null
  echo "$output" | jq -e '.grade' >/dev/null
  # Has all dimensions
  echo "$output" | jq -e '.dimensions.config_completeness' >/dev/null
  echo "$output" | jq -e '.dimensions.rule_coverage' >/dev/null
  echo "$output" | jq -e '.dimensions.hook_coverage' >/dev/null
  echo "$output" | jq -e '.dimensions.plugin_alignment' >/dev/null
}

@test "score_global returns high score for well-configured setup" {
  local json='{
    "claude_md":{"exists":true,"lines":200},
    "persona":{"persona":"senior-engineer","axes":{"a":"1","b":"2","c":"3","d":"4"}},
    "rules":{"count":7},
    "hooks":[1,2,3,4,5,6,7],
    "plugins":{"group":"full","count":18},
    "install":{"install_timestamp":"2026-03-17T00:00:00Z"}
  }'
  run score_global "$json"
  assert_success
  local total
  total=$(echo "$output" | jq -r '.total')
  # Should be 90+ for a perfect setup
  [ "$total" -ge 90 ]
}

@test "score_global returns low score for empty setup" {
  local json='{
    "claude_md":{"exists":false,"lines":0},
    "persona":{"persona":"unknown","axes":{}},
    "rules":{"count":0},
    "hooks":[],
    "plugins":{"group":"unknown","count":0},
    "install":{"install_timestamp":"unknown"}
  }'
  run score_global "$json"
  assert_success
  local total
  total=$(echo "$output" | jq -r '.total')
  [ "$total" -lt 30 ]
}

# ── Repo Score ───────────────────────────────────────────────

@test "score_repo produces valid JSON" {
  local json='{
    "claude_md":{"exists":true,"lines":50},
    "rules":{"count":3},
    "doc_chain":{"project_md":true,"requirements_md":false,"roadmap_md":true,"dismissed":false}
  }'
  run score_repo "$json"
  assert_success
  echo "$output" | jq -e '.total' >/dev/null
  echo "$output" | jq -e '.grade' >/dev/null
  echo "$output" | jq -e '.dimensions.config' >/dev/null
  echo "$output" | jq -e '.dimensions.doc_chain' >/dev/null
  echo "$output" | jq -e '.dimensions.rules' >/dev/null
}

@test "score_repo returns high score for well-configured repo" {
  local json='{
    "claude_md":{"exists":true,"lines":50},
    "rules":{"count":5},
    "doc_chain":{"project_md":true,"requirements_md":true,"roadmap_md":true,"dismissed":false}
  }'
  run score_repo "$json"
  assert_success
  local total
  total=$(echo "$output" | jq -r '.total')
  [ "$total" -ge 80 ]
}

@test "score_repo gives partial credit for dismissed doc chain" {
  local json='{
    "claude_md":{"exists":true,"lines":50},
    "rules":{"count":3},
    "doc_chain":{"project_md":false,"requirements_md":false,"roadmap_md":false,"dismissed":true}
  }'
  run score_repo "$json"
  assert_success
  local doc_score
  doc_score=$(echo "$output" | jq -r '.dimensions.doc_chain.score')
  assert_equal "$doc_score" "60"
}

@test "score_repo returns F for empty repo config" {
  local json='{
    "claude_md":{"exists":false,"lines":0},
    "rules":{"count":0},
    "doc_chain":{"project_md":false,"requirements_md":false,"roadmap_md":false,"dismissed":false}
  }'
  run score_repo "$json"
  assert_success
  local grade
  grade=$(echo "$output" | jq -r '.grade')
  assert_equal "$grade" "F"
}
