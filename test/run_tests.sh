#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Runner — convenience wrapper for bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Usage:
#   ./test/run_tests.sh              # run all tests (parallel suites)
#   ./test/run_tests.sh unit         # run unit tests only
#   ./test/run_tests.sh integration  # run integration tests only
#   ./test/run_tests.sh validation   # run validation tests only
#   ./test/run_tests.sh <file.bats>  # run a specific test file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS="$SCRIPT_DIR/libs/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
  echo "ERROR: bats not found. Run: git submodule update --init --recursive"
  exit 1
fi

# Check for jq (required by most tests)
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if [ $# -eq 0 ]; then
  # Run all suites in parallel — each suite gets its own bats process
  echo "Running all tests..."
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  "$BATS" --recursive "$SCRIPT_DIR/unit"       > "$tmpdir/unit.tap"       2>&1 &
  pid_unit=$!
  "$BATS" --recursive "$SCRIPT_DIR/integration" > "$tmpdir/integration.tap" 2>&1 &
  pid_int=$!
  "$BATS" --recursive "$SCRIPT_DIR/validation"  > "$tmpdir/validation.tap"  2>&1 &
  pid_val=$!

  rc=0
  wait "$pid_unit" || rc=1
  wait "$pid_int"  || rc=1
  wait "$pid_val"  || rc=1

  # Output results in order
  cat "$tmpdir/unit.tap"
  cat "$tmpdir/integration.tap"
  cat "$tmpdir/validation.tap"

  exit "$rc"
elif [ -f "$1" ]; then
  # Run specific file
  "$BATS" "$1"
elif [ -d "$SCRIPT_DIR/$1" ]; then
  # Run directory (unit, integration, validation)
  echo "Running $1 tests..."
  "$BATS" --recursive "$SCRIPT_DIR/$1"
else
  echo "Usage: $0 [unit|integration|validation|<file.bats>]"
  exit 1
fi
