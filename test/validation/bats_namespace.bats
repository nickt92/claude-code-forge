#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# bats namespace — shipped code must not shadow test-harness functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test files load the bats helpers and then source project libs. Any function
# defined in forge/ or lib/ that shares a name with a bats helper silently
# replaces it for the rest of that file.
#
# This is not hypothetical. lib/ui.sh once defined fail(), which is the
# primitive every assert_* helper calls to fail a test. Because it printed a
# message and returned 0, every assertion after `source lib/ui.sh` reported
# success no matter what. The suite claimed 722 passing while 13 tests were
# broken. See forge_fail() in lib/ui.sh.
#
# This guards the whole class, not just that one name.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

# Function names defined by the vendored bats helper libraries.
_bats_helper_functions() {
  grep -rhoE '^[a-z_][a-z0-9_]*\(\)' \
    "$TEST_DIR/libs/bats-support/src" \
    "$TEST_DIR/libs/bats-assert/src" \
    "$TEST_DIR/libs/bats-file/src" \
    2>/dev/null | tr -d '()' | sort -u
}

# Function names defined by shipped code that tests source.
_forge_functions() {
  grep -rhoE '^[a-z_][a-z0-9_]*\(\) \{' \
    "$PROJECT_ROOT/forge" \
    "$PROJECT_ROOT/lib" \
    2>/dev/null | sed 's/() {//' | sort -u
}

@test "no shipped function shadows a bats helper function" {
  local collisions
  collisions=$(comm -12 <(_bats_helper_functions) <(_forge_functions))

  if [ -n "$collisions" ]; then
    printf 'Shipped code defines function names owned by the bats helpers.\n' >&2
    printf 'Sourcing those libs in a test replaces the helper and can silently\n' >&2
    printf 'disable assertions. Rename the shipped function (see forge_fail).\n\n' >&2
    printf 'Collisions:\n%s\n' "$collisions" >&2
  fi

  [ -z "$collisions" ]
}

@test "the collision scan actually finds functions on both sides" {
  # Guards against the test passing because a path changed and one side is
  # empty — which would make the check above vacuously true.
  [ "$(_bats_helper_functions | wc -l | tr -d ' ')" -gt 20 ]
  [ "$(_forge_functions | wc -l | tr -d ' ')" -gt 50 ]
}
