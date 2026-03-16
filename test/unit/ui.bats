#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# UI Library — unit tests for lib/ui.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox

  # Source ui.sh (non-TTY context in test runner)
  source "$SCRIPT_DIR/lib/ui.sh"
}

teardown() {
  teardown_sandbox
}

# ── Output Functions ─────────────────────────────────────────

@test "ok() prints checkmark and message" {
  run ok "Everything worked"
  assert_success
  assert_output --partial "Everything worked"
}

@test "warn() prints warning and message" {
  run warn "Something iffy"
  assert_success
  assert_output --partial "Something iffy"
}

@test "fail() prints error and message" {
  run fail "Something broke"
  assert_success
  assert_output --partial "Something broke"
}

@test "info() prints dim message" {
  run info "Secondary detail"
  assert_success
  assert_output --partial "Secondary detail"
}

@test "step() prints section header" {
  run step "Installing files"
  assert_success
  assert_output --partial "Installing files"
  assert_output --partial "==>"
}

@test "banner() prints hammer and title" {
  run banner "Claude Code Forge"
  assert_success
  assert_output --partial "Claude Code Forge"
}

# ── Quiet Mode ───────────────────────────────────────────────

@test "ok() suppressed in quiet mode" {
  UI_QUIET=true run ok "Should not appear"
  assert_success
  assert_output ""
}

@test "info() suppressed in quiet mode" {
  UI_QUIET=true run info "Should not appear"
  assert_success
  assert_output ""
}

@test "step() suppressed in quiet mode" {
  UI_QUIET=true run step "Should not appear"
  assert_success
  assert_output ""
}

@test "banner() suppressed in quiet mode" {
  UI_QUIET=true run banner "Should not appear"
  assert_success
  assert_output ""
}

@test "fail() prints even in quiet mode" {
  UI_QUIET=true run fail "Critical error"
  assert_success
  assert_output --partial "Critical error"
}

@test "warn() prints even in quiet mode" {
  UI_QUIET=true run warn "Important warning"
  assert_success
  assert_output --partial "Important warning"
}

# ── Progress Counter ─────────────────────────────────────────

@test "progress_start/tick/done produces output" {
  # In non-TTY (test runner), progress uses simple fallback
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; progress_start 3 "Testing"; progress_tick; progress_tick; progress_tick; progress_done "3 items done"'
  assert_success
  assert_output --partial "3 items done"
}

@test "progress counter suppressed in quiet mode" {
  run bash -c 'export UI_QUIET=true; source "'"$SCRIPT_DIR"'/lib/ui.sh"; progress_start 2 "Testing"; progress_tick; progress_tick; progress_done "2 done"'
  assert_success
  # ok() in progress_done is suppressed in quiet mode
  assert_output ""
}

# ── Color Detection ──────────────────────────────────────────

@test "NO_COLOR disables colors" {
  run bash -c 'export NO_COLOR=1; source "'"$SCRIPT_DIR"'/lib/ui.sh"; echo "$_UI_USE_COLOR"'
  assert_output "false"
}

@test "TERM=dumb disables colors" {
  run bash -c 'export TERM=dumb; source "'"$SCRIPT_DIR"'/lib/ui.sh"; echo "$_UI_USE_COLOR"'
  assert_output "false"
}

@test "non-TTY disables colors" {
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; echo "$_UI_USE_COLOR"'
  assert_output "false"
}

# ── TTY Detection ────────────────────────────────────────────

@test "non-TTY sets _UI_IS_TTY to false" {
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; echo "$_UI_IS_TTY"'
  assert_output "false"
}

# ── Spin (non-TTY fallback) ──────────────────────────────────

@test "spin runs command and shows done on success" {
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; spin "Working" true'
  assert_success
  assert_output --partial "Working..."
  assert_output --partial "done"
}

@test "spin shows failed on command failure" {
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; spin "Breaking" false'
  assert_failure
  assert_output --partial "Breaking..."
  assert_output --partial "failed"
}

# ── Bar Chart ────────────────────────────────────────────────

@test "bar() renders proportional bar with label and count" {
  run bar "aws_key" 5 10
  assert_success
  assert_output --partial "aws_key"
  assert_output --partial "5"
  # Non-TTY uses # and .
  assert_output --partial "#####....."
}

@test "bar() handles zero value" {
  run bar "empty" 0 10
  assert_success
  assert_output --partial ".........."
  assert_output --partial "0"
}

@test "bar() handles value equal to total (full bar)" {
  run bar "full" 10 10
  assert_success
  assert_output --partial "##########"
  assert_output --partial "10"
}

@test "bar() uses non-TTY fallback characters" {
  # In test runner (non-TTY), should use # and .
  run bash -c 'source "'"$SCRIPT_DIR"'/lib/ui.sh"; bar "test" 3 10'
  assert_success
  assert_output --partial "###......."
}

@test "bar() suppressed in quiet mode" {
  UI_QUIET=true run bar "hidden" 5 10
  assert_success
  assert_output ""
}

# ── Test Override Pattern ────────────────────────────────────

@test "functions can be overridden after source" {
  # This is the pattern tests use — redefine after source
  ok() { echo "CUSTOM: $1"; }
  run ok "test message"
  assert_output "CUSTOM: test message"
}
