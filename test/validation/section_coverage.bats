#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Section Coverage — validation tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Ensures every axis value maps to an existing section file
# and no orphan sections exist.

setup() {
  load '../helpers/test_helper'
  SECTIONS_DIR="$PROJECT_ROOT/templates/sections"
  PROFILES_DIR="$PROJECT_ROOT/templates/profiles"
}

# ── Every Axis Value Maps to a Section File ──────────────────

@test "every communication axis value has a corresponding section file" {
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.communication' "$profile")
    assert [ -f "$SECTIONS_DIR/communication-${val}.md" ]
  done
}

@test "every autonomy axis value has a corresponding section file" {
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.autonomy' "$profile")
    assert [ -f "$SECTIONS_DIR/autonomy-${val}.md" ]
  done
}

@test "every workflow axis value has a corresponding section file" {
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.workflow' "$profile")
    assert [ -f "$SECTIONS_DIR/workflow-${val}.md" ]
  done
}

@test "every depth axis value has a corresponding section file" {
  for profile in "$PROFILES_DIR"/*.json; do
    local val
    val=$(jq -r '.axes.depth' "$profile")
    assert [ -f "$SECTIONS_DIR/depth-${val}.md" ]
  done
}

@test "every quality value has a corresponding section file" {
  for profile in "$PROFILES_DIR"/*.json; do
    local quals
    quals=$(jq -r '.quality[]' "$profile")
    for q in $quals; do
      assert [ -f "$SECTIONS_DIR/quality-${q}.md" ]
    done
  done
}

# ── Base Section Exists ──────────────────────────────────────

@test "base.md section exists" {
  assert [ -f "$SECTIONS_DIR/base.md" ]
}

# ── No Orphan Sections ──────────────────────────────────────

@test "no orphan section files exist" {
  # Collect all expected section filenames from profiles
  local expected_sections=("base.md" "quality-core.md")

  # Add axis-based sections
  for profile in "$PROFILES_DIR"/*.json; do
    expected_sections+=("communication-$(jq -r '.axes.communication' "$profile").md")
    expected_sections+=("autonomy-$(jq -r '.axes.autonomy' "$profile").md")
    expected_sections+=("workflow-$(jq -r '.axes.workflow' "$profile").md")
    expected_sections+=("depth-$(jq -r '.axes.depth' "$profile").md")
    for q in $(jq -r '.quality[]' "$profile"); do
      expected_sections+=("quality-${q}.md")
    done
  done

  # Deduplicate
  local unique_expected
  unique_expected=$(printf '%s\n' "${expected_sections[@]}" | sort -u)

  # Check every actual section file is in expected list
  for section_file in "$SECTIONS_DIR"/*.md; do
    local basename
    basename=$(basename "$section_file")
    run grep -Fx "$basename" <<< "$unique_expected"
    assert_success
  done
}

# ── All Sections Are Non-Empty ───────────────────────────────

@test "all section files are non-empty" {
  for section_file in "$SECTIONS_DIR"/*.md; do
    local size
    size=$(wc -c < "$section_file" | tr -d ' ')
    assert [ "$size" -gt 0 ]
  done
}
