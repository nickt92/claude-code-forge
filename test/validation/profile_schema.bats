#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Profile Schema — validation tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Validates structural integrity of all profile JSON files.

setup() {
  load '../helpers/test_helper'
  PROFILES_DIR="$PROJECT_ROOT/templates/profiles"
}

# ── Valid JSON ───────────────────────────────────────────────

@test "all profile files are valid JSON" {
  for profile in "$PROFILES_DIR"/*.json; do
    run jq -e '.' "$profile"
    assert_success
  done
}

# ── Required Keys ────────────────────────────────────────────

@test "all profiles have required top-level keys" {
  local required_keys=("schema_version" "persona" "label" "description" "axes" "quality")
  for profile in "$PROFILES_DIR"/*.json; do
    for key in "${required_keys[@]}"; do
      run jq -e ".$key" "$profile"
      assert_success
    done
  done
}

@test "all profiles have all 4 axis keys" {
  local axis_keys=("communication" "autonomy" "workflow" "depth")
  for profile in "$PROFILES_DIR"/*.json; do
    for key in "${axis_keys[@]}"; do
      run jq -e ".axes.$key" "$profile"
      assert_success
    done
  done
}

# ── Type Validation ──────────────────────────────────────────

@test "schema_version is a number equal to 1" {
  for profile in "$PROFILES_DIR"/*.json; do
    run jq -e '.schema_version == 1' "$profile"
    assert_success
  done
}

@test "persona is a non-empty string" {
  for profile in "$PROFILES_DIR"/*.json; do
    run jq -e '.persona | type == "string" and length > 0' "$profile"
    assert_success
  done
}

@test "quality is a non-empty array" {
  for profile in "$PROFILES_DIR"/*.json; do
    run jq -e '.quality | type == "array" and length > 0' "$profile"
    assert_success
  done
}

# ── Axis Values from Allowed Sets ────────────────────────────

@test "communication axis values are from allowed set" {
  local allowed='["plain","technical","expert"]'
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.communication' "$profile")
    run jq -e --arg v "$val" '. as $set | $v | IN($set[])' <<< "$allowed"
    assert_success
  done
}

@test "autonomy axis values are from allowed set" {
  local allowed='["guided","moderate","high"]'
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.autonomy' "$profile")
    run jq -e --arg v "$val" '. as $set | $v | IN($set[])' <<< "$allowed"
    assert_success
  done
}

@test "workflow axis values are from allowed set" {
  local allowed='["simplified","standard","advanced"]'
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.workflow' "$profile")
    run jq -e --arg v "$val" '. as $set | $v | IN($set[])' <<< "$allowed"
    assert_success
  done
}

@test "depth axis values are from allowed set" {
  local allowed='["conceptual","practical","engineering"]'
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.depth' "$profile")
    run jq -e --arg v "$val" '. as $set | $v | IN($set[])' <<< "$allowed"
    assert_success
  done
}

# ── Persona Matches Filename ─────────────────────────────────

@test "persona field matches filename for all profiles" {
  for profile in "$PROFILES_DIR"/*.json; do
    local filename persona
    filename=$(basename "$profile" .json)
    persona=$(jq -r '.persona' "$profile")
    assert [ "$filename" = "$persona" ]
  done
}

# ── No Duplicate Personas ────────────────────────────────────

@test "no duplicate persona names across profiles" {
  local personas
  personas=$(for p in "$PROFILES_DIR"/*.json; do jq -r '.persona' "$p"; done | sort)
  local unique
  unique=$(echo "$personas" | sort -u)
  assert [ "$personas" = "$unique" ]
}
