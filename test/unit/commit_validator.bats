#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Commit Validator Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/commit-validator.sh"
}

teardown() {
  teardown_sandbox
}

# Helper: run hook with given command string via temp file (avoids JSON escaping issues)
run_hook() {
  local cmd="$1"
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  jq -n --arg c "$cmd" '{"tool_input":{"command":$c}}' > "$tmpfile"
  bash "$HOOK" < "$tmpfile"
}

run_hook_with_exit() {
  local cmd="$1"
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  jq -n --arg c "$cmd" '{"tool_input":{"command":$c}}' > "$tmpfile"
  bash "$HOOK" < "$tmpfile" 2>/dev/null
}

# ── Gate 1: AI Attribution Blocking ──────────────────────────

@test "blocks Co-Authored-By: Claude" {
  run run_hook 'git commit -m "feat: add login" -m "Co-Authored-By: Claude"'
  assert_failure 2
}

@test "blocks Co-Authored-By: Anthropic" {
  run run_hook 'git commit -m "feat: add login" -m "Co-Authored-By: Anthropic"'
  assert_failure 2
}

@test "blocks Generated with Claude" {
  run run_hook 'git commit -m "feat: add login\n\nGenerated with Claude"'
  assert_failure 2
}

@test "blocks Generated with Claude Code" {
  run run_hook 'git commit -m "feat: add login\n\nGenerated with Claude Code"'
  assert_failure 2
}

@test "blocks case-insensitive co-authored-by: claude" {
  run run_hook 'git commit -m "feat: add login" -m "co-authored-by: Claude"'
  assert_failure 2
}

@test "blocks AI attribution in heredoc format" {
  run run_hook 'git commit -m "$(cat <<'\''EOF'\''
feat: add login

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"'
  assert_failure 2
}

@test "outputs BLOCKED message on AI attribution" {
  run run_hook 'git commit -m "Co-Authored-By: Claude"'
  assert_output --partial "BLOCKED"
  assert_output --partial "AI attribution"
}

# ── Gate 2: Conventional Commit Warning ──────────────────────

@test "warns on non-conventional commit message" {
  create_test_profile "senior-engineer" "high" "advanced"
  run run_hook_with_exit 'git commit -m "fixed stuff"'
  assert_success
  assert_output --partial "hookSpecificOutput"
  assert_output --partial "WARNING"
}

@test "passes valid conventional commit silently" {
  run run_hook_with_exit 'git commit -m "feat(auth): add login flow"'
  assert_success
  assert_output ''
}

@test "passes feat: without scope" {
  run run_hook_with_exit 'git commit -m "feat: add login"'
  assert_success
  assert_output ''
}

@test "passes fix(payments): format" {
  run run_hook_with_exit 'git commit -m "fix(payments): handle refund edge case"'
  assert_success
  assert_output ''
}

@test "passes chore(deps): format" {
  run run_hook_with_exit 'git commit -m "chore(deps): bump lodash"'
  assert_success
  assert_output ''
}

@test "passes breaking change with bang" {
  run run_hook_with_exit 'git commit -m "feat(api)!: remove v1 endpoints"'
  assert_success
  assert_output ''
}

@test "passes all valid conventional types" {
  local types=(feat fix chore docs test refactor style perf ci build revert)
  for t in "${types[@]}"; do
    run run_hook_with_exit "git commit -m \"${t}: test message\""
    assert_success
  done
}

# ── Message Extraction ───────────────────────────────────────

@test "extracts message from double-quoted -m" {
  run run_hook_with_exit 'git commit -m "fixed stuff"'
  assert_success
  assert_output --partial "WARNING"
}

@test "extracts message from single-quoted -m" {
  run run_hook_with_exit "git commit -m 'fixed stuff'"
  assert_success
  assert_output --partial "WARNING"
}

# ── Passthrough Cases ────────────────────────────────────────

@test "passes merge commits" {
  run run_hook_with_exit 'git commit -m "Merge branch '\''feature'\'' into main"'
  assert_success
  assert_output ''
}

@test "passes revert commits via revert type prefix" {
  # The revert conventional type is always allowed
  run run_hook_with_exit 'git commit -m "revert: undo bad feature"'
  assert_success
  assert_output ''
}

@test "allows git-generated revert through (no block)" {
  # Git's revert format with inner quotes can't be cleanly extracted
  # by the hook's simple regex — hook allows through (exit 0, may warn)
  run run_hook_with_exit 'git commit -m "Revert \"feat: bad feature\""'
  assert_success
}

@test "ignores non-git commands" {
  run run_hook_with_exit 'ls -la'
  assert_success
  assert_output ''
}

@test "ignores git commands that are not commit" {
  run run_hook_with_exit 'git status'
  assert_success
  assert_output ''
}

@test "ignores git push" {
  run run_hook_with_exit 'git push origin main'
  assert_success
  assert_output ''
}

# ── Persona-aware Warning Tone ───────────────────────────────

@test "simplified workflow gets plain English warning" {
  create_test_profile "vibe-coder" "guided" "simplified"
  run run_hook_with_exit 'git commit -m "fixed stuff"'
  assert_success
  assert_output --partial "should start with a type like feat:"
}

@test "advanced workflow gets technical warning" {
  create_test_profile "senior-engineer" "high" "advanced"
  run run_hook_with_exit 'git commit -m "fixed stuff"'
  assert_success
  assert_output --partial "conventional commit format"
}

# ── Error Paths ──────────────────────────────────────────────

@test "handles missing profile gracefully (defaults to advanced)" {
  rm -f "$CLAUDE_DIR/profile.json"
  run run_hook_with_exit 'git commit -m "fixed stuff"'
  assert_success
  assert_output --partial "conventional commit format"
}

@test "handles empty command input" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"\"}}" | bash "$0"' "$HOOK"
  assert_success
}

@test "handles malformed JSON input" {
  run bash -c 'echo "not json" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}
