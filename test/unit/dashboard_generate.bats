#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests for dashboard HTML generation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/dashboard/generate.sh"
}

teardown() {
  teardown_sandbox
}

# ── Emit Functions ───────────────────────────────────────────

@test "emit_styles produces CSS" {
  run _emit_styles
  assert_success
  assert_output --partial "<style>"
  assert_output --partial "--c-success"
  assert_output --partial "prefers-color-scheme"
}

@test "emit_head produces valid HTML head" {
  run _emit_head
  assert_success
  assert_output --partial "<!DOCTYPE html>"
  assert_output --partial "<meta charset"
  assert_output --partial "<title>Forge Dashboard</title>"
  assert_output --partial "</head>"
}

@test "emit_header produces header with theme toggle" {
  run _emit_header
  assert_success
  assert_output --partial "header"
  assert_output --partial "themeToggle"
  assert_output --partial "role=\"banner\""
}

@test "emit_hero produces hero section" {
  run _emit_hero
  assert_success
  assert_output --partial "heroScore"
  assert_output --partial "heroStats"
}

@test "emit_repo_toolbar includes search and filters" {
  run _emit_repo_toolbar
  assert_success
  assert_output --partial "searchInput"
  assert_output --partial "sortSelect"
  assert_output --partial "filterSelect"
  assert_output --partial "focusToggle"
}

@test "emit_help_modal includes keyboard shortcuts" {
  run _emit_help_modal
  assert_success
  assert_output --partial "Keyboard Shortcuts"
  assert_output --partial "j / k"
  assert_output --partial "role=\"dialog\""
}

@test "emit_toast_and_live includes ARIA live region" {
  run _emit_toast_and_live
  assert_success
  assert_output --partial "aria-live=\"polite\""
  assert_output --partial "toastContainer"
  assert_output --partial "liveRegion"
}

# ── Data Injection ───────────────────────────────────────────

@test "emit_data injects JSON into script tag" {
  run _emit_data '{"test": true}'
  assert_success
  assert_output --partial 'const DATA = {"test": true};'
}

@test "emit_data handles complex JSON" {
  local json='{"global":{"persona":{"name":"test"}},"repos":[]}'
  run _emit_data "$json"
  assert_success
  assert_output --partial "const DATA ="
}

# ── Script ───────────────────────────────────────────────────

@test "emit_script produces JavaScript with init function" {
  run _emit_script
  assert_success
  assert_output --partial "<script>"
  assert_output --partial "function init()"
  assert_output --partial "renderHero"
  assert_output --partial "renderRepoCards"
}

@test "emit_script includes keyboard navigation" {
  run _emit_script
  assert_success
  assert_output --partial "initKeyboard"
  assert_output --partial "navigateCards"
}

@test "emit_script includes clipboard support" {
  run _emit_script
  assert_success
  assert_output --partial "copyText"
  assert_output --partial "clipboard"
  assert_output --partial "execCommand"
}

@test "emit_script includes theme toggle" {
  run _emit_script
  assert_success
  assert_output --partial "toggleTheme"
  assert_output --partial "localStorage"
}

@test "emit_script includes focus mode" {
  run _emit_script
  assert_success
  assert_output --partial "toggleFocusMode"
  assert_output --partial "focus-mode"
}

# ── Full Generation ──────────────────────────────────────────

@test "generate_dashboard creates valid HTML file" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{},"global_score":{"total":85,"grade":"B","dimensions":{}},"repos":[],"generated_at":"2026-03-17"}'

  run generate_dashboard "$json" "$output"
  assert_success
  assert [ -f "$output" ]

  # Check structure
  run cat "$output"
  assert_output --partial "<!DOCTYPE html>"
  assert_output --partial "</html>"
  assert_output --partial "const DATA ="
  assert_output --partial "Forge Dashboard"
}

@test "generate_dashboard creates parent directories" {
  local output="$TEST_SANDBOX/deep/nested/dir/dashboard.html"
  local json='{"global":{},"global_score":{"total":50,"grade":"F","dimensions":{}},"repos":[],"generated_at":"2026-03-17"}'

  run generate_dashboard "$json" "$output"
  assert_success
  assert [ -f "$output" ]
}

@test "generate_dashboard embeds data correctly" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{"persona":{"persona":"test"}},"global_score":{"total":70,"grade":"C","dimensions":{}},"repos":[{"name":"myrepo","path":"/test"}],"generated_at":"now"}'

  generate_dashboard "$json" "$output"
  # Verify JSON is embedded
  run grep -c 'const DATA' "$output"
  assert_output "1"
  # Verify repo name appears in data
  run grep -c 'myrepo' "$output"
  assert [ "$output" -ge 1 ]
}

@test "generate_dashboard includes accessibility features" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{},"global_score":{"total":80,"grade":"B","dimensions":{}},"repos":[],"generated_at":"now"}'

  generate_dashboard "$json" "$output"
  local content
  content=$(cat "$output")

  # ARIA landmarks
  echo "$content" | grep -q 'role="banner"'
  echo "$content" | grep -q 'role="main"'
  echo "$content" | grep -q 'role="contentinfo"'
  echo "$content" | grep -q 'role="dialog"'
  echo "$content" | grep -q 'aria-live="polite"'
  echo "$content" | grep -q 'sr-only'
}

@test "generate_dashboard includes dark mode CSS" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{},"global_score":{"total":80,"grade":"B","dimensions":{}},"repos":[],"generated_at":"now"}'

  generate_dashboard "$json" "$output"
  run grep -c 'prefers-color-scheme' "$output"
  assert [ "$output" -ge 1 ]
  run grep -c 'data-theme' "$output"
  assert [ "$output" -ge 1 ]
}

@test "generate_dashboard includes print styles" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{},"global_score":{"total":80,"grade":"B","dimensions":{}},"repos":[],"generated_at":"now"}'

  generate_dashboard "$json" "$output"
  run grep -c '@media print' "$output"
  assert [ "$output" -ge 1 ]
}

@test "generate_dashboard includes reduced motion support" {
  local output="$TEST_SANDBOX/dashboard.html"
  local json='{"global":{},"global_score":{"total":80,"grade":"B","dimensions":{}},"repos":[],"generated_at":"now"}'

  generate_dashboard "$json" "$output"
  run grep -c 'prefers-reduced-motion' "$output"
  assert [ "$output" -ge 1 ]
}
