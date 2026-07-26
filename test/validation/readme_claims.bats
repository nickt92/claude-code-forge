#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# README claims — numbers in the README must match reality
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The README advertises test counts, hook counts and rules counts. Every one
# of them is hand-maintained, and they had all drifted: it claimed 850+ tests
# (697 CLI + 162 Swift) when the real figures were 730 and 189, and drifted
# again within a day of being corrected.
#
# version_sync.bats already guards the version number this way. These guard
# the rest, so the front page cannot quietly become fiction.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  README="$PROJECT_ROOT/README.md"
}

teardown() {
  teardown_sandbox
}

_cli_test_count() {
  grep -h '^@test' \
    "$PROJECT_ROOT"/test/unit/*.bats \
    "$PROJECT_ROOT"/test/integration/*.bats \
    "$PROJECT_ROOT"/test/validation/*.bats | wc -l | tr -d ' '
}

_swift_test_count() {
  grep -rhoE '^[[:space:]]*func test[A-Za-z0-9_]*\(' \
    "$PROJECT_ROOT/app/ForgeDesktopCore/Tests" --include='*.swift' | wc -l | tr -d ' '
}

@test "README CLI test count matches the suite" {
  local actual
  actual=$(_cli_test_count)
  assert [ "$actual" -gt 0 ]
  run grep -c "${actual} CLI (bats-core)" "$README"
  assert_success
  assert_output "1"
}

@test "README Swift test count matches the desktop suite" {
  local actual
  actual=$(_swift_test_count)
  assert [ "$actual" -gt 0 ]
  run grep -c "+ ${actual} Swift" "$README"
  assert_success
  assert_output "1"
}

@test "README total test count is the sum of both suites" {
  local total
  total=$(( $(_cli_test_count) + $(_swift_test_count) ))
  # Appears in the header badge line and the testing section heading.
  run grep -c "${total} Tests\|${total} automated tests" "$README"
  assert_success
  assert [ "$output" -ge 2 ]
}

@test "README suite file counts match the directories" {
  local unit integration validation
  unit=$(find "$PROJECT_ROOT/test/unit" -name '*.bats' | wc -l | tr -d ' ')
  integration=$(find "$PROJECT_ROOT/test/integration" -name '*.bats' | wc -l | tr -d ' ')
  validation=$(find "$PROJECT_ROOT/test/validation" -name '*.bats' | wc -l | tr -d ' ')

  run grep -c "^| \*\*Unit\*\* | ${unit} |" "$README"
  assert_output "1"
  run grep -c "^| \*\*Integration\*\* | ${integration} |" "$README"
  assert_output "1"
  run grep -c "^| \*\*Validation\*\* | ${validation} |" "$README"
  assert_output "1"
}

@test "README hook count matches the hooks forge ships" {
  source "$PROJECT_ROOT/lib/forge-inventory.sh"
  local actual
  actual=$(forge_shipped_hooks | grep -c .)
  assert [ "$actual" -gt 0 ]
  run grep -c "\*\*${actual} Hooks\*\*" "$README"
  assert_output "1"
}

@test "README rules count matches the rules forge ships" {
  source "$PROJECT_ROOT/lib/forge-inventory.sh"
  local actual
  actual=$(forge_shipped_rules | grep -c .)
  assert [ "$actual" -gt 0 ]
  run grep -c "\*\*${actual} Rules Files\*\*" "$README"
  assert_output "1"
}
