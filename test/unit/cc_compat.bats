#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cc-compat — what forge needs from Claude Code, verified not assumed
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge has been broken twice by Claude Code changing underneath it, and
# neither was a version problem:
#   - `claude plugins add` was removed, so install installed zero plugins and
#     reported success;
#   - an `if:` filter at the wrong nesting level was silently discarded.
# So these check capability, not just a version string.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/cc-compat.sh"

  # A fake `claude` on PATH, so these never depend on the real one.
  FAKE_BIN="$TEST_SANDBOX/bin"
  mkdir -p "$FAKE_BIN"
  PATH="$FAKE_BIN:$PATH"
}

teardown() {
  teardown_sandbox
}

# Write a fake claude whose --help output mimics commander's format.
_fake_claude() {
  local version="${1:-2.1.220}"
  local plugin_cmds="${2:-install|i\n  marketplace\n  uninstall}"
  local marketplace_cmds="${3:-add\n  list\n  remove}"
  cat > "$FAKE_BIN/claude" <<EOF
#!/bin/bash
if [ "\$1" = "--version" ]; then echo "$version (Claude Code)"; exit 0; fi
if [ "\$1" = "plugin" ] && [ "\$2" = "marketplace" ]; then
  printf 'Usage: claude plugin marketplace\n\nCommands:\n  %b\n' "$marketplace_cmds"; exit 0
fi
if [ "\$1" = "plugin" ]; then
  printf 'Usage: claude plugin\n\nCommands:\n  %b\n' "$plugin_cmds"; exit 0
fi
printf 'Usage: claude\n\nCommands:\n  plugin\n  doctor\n'
EOF
  chmod +x "$FAKE_BIN/claude"
}

# ── Version comparison ───────────────────────────────────────

@test "cc_version_ge compares across all three components" {
  cc_version_ge "2.1.220" "2.0.0"
  cc_version_ge "2.1.220" "2.1.220"
  cc_version_ge "2.2.0" "2.1.999"
  ! cc_version_ge "1.9.9" "2.0.0"
  ! cc_version_ge "2.1.9" "2.1.10"
}

@test "cc_version_ge treats missing components as zero" {
  cc_version_ge "2.1" "2.1.0"
  cc_version_ge "3" "2.9.9"
}

@test "cc_version_ge tolerates a pre-release suffix" {
  cc_version_ge "2.1.220-beta" "2.1.220"
}

@test "cc_detect_version parses the version out of the banner" {
  _fake_claude "2.3.4"
  run cc_detect_version
  assert_success
  assert_output "2.3.4"
}

# ── Verb probing ─────────────────────────────────────────────

@test "cc_probe_cli_verb finds a nested subcommand" {
  _fake_claude
  run cc_probe_cli_verb "plugin marketplace add"
  assert_success
}

@test "cc_probe_cli_verb sees through an alias suffix" {
  # commander prints "install|i [options] <plugin>" — the name is followed by
  # a pipe, not whitespace, which an earlier version of this failed to match
  # and would have blocked every install.
  _fake_claude
  run cc_probe_cli_verb "plugin install"
  assert_success
}

@test "cc_probe_cli_verb reports a removed verb as absent" {
  # This is the `claude plugins add` regression, reproduced.
  _fake_claude "2.1.220" "uninstall\n  marketplace"
  run cc_probe_cli_verb "plugin install"
  assert_failure
}

@test "cc_probe_cli_verb reports absent when an intermediate group is gone" {
  _fake_claude "2.1.220" "install|i"
  run cc_probe_cli_verb "plugin marketplace add"
  assert_failure
}

@test "cc_probe_cli_verb cannot tell when claude is missing" {
  # Minimal PATH: still has coreutils (teardown needs rm) but not claude,
  # which lives in ~/.local/bin.
  PATH="/usr/bin:/bin"
  hash -r                             # bash caches resolved command paths
  run cc_probe_cli_verb "plugin install"
  assert_equal "$status" 2
}

@test "cc_probe_cli_verb does not mistake a wrapped description for a command" {
  cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then echo "2.1.220 (Claude Code)"; exit 0; fi
printf 'Usage: claude plugin\n\nCommands:\n  install|i [options] <plugin>   Install a plugin from\n                                 available marketplaces\n'
EOF
  chmod +x "$FAKE_BIN/claude"
  # "available" is a wrapped description line, not a subcommand
  run cc_probe_cli_verb "plugin available"
  assert_failure
}

# ── The gate ─────────────────────────────────────────────────

@test "cc_compat_check passes against a compatible Claude Code" {
  _fake_claude "2.1.220"
  run cc_compat_check true
  assert_success
}

@test "cc_compat_check refuses a version below the minimum" {
  _fake_claude "1.5.0"
  run cc_compat_check true
  assert_failure
  assert_output --partial "older than the minimum"
}

@test "cc_compat_check refuses when a required verb is gone" {
  _fake_claude "2.1.220" "uninstall\n  marketplace"
  run cc_compat_check true
  assert_failure
  assert_output --partial "no longer provides"
  assert_output --partial "plugin install"
}

@test "cc_compat_check fails when Claude Code is absent entirely" {
  # Minimal PATH: still has coreutils (teardown needs rm) but not claude,
  # which lives in ~/.local/bin.
  PATH="/usr/bin:/bin"
  hash -r                             # bash caches resolved command paths
  run cc_compat_check true
  assert_failure
  assert_output --partial "not found"
}

@test "cc_compat_check proceeds on a newer-than-tested version" {
  # Refusing to run on a newer Claude Code would be worse than the risk.
  _fake_claude "9.9.9"
  run cc_compat_check true
  assert_success
}

@test "cc_compat_check proceeds when the version cannot be parsed" {
  # Unknown is not the same as unsupported — a custom build that reports no
  # semver must not block install.
  _fake_claude "some custom build"
  run cc_compat_check true
  assert_success
  assert_output --partial "Could not determine"
}

@test "cc_compat_check is a no-op when the contract file is missing" {
  _fake_claude
  CC_COMPAT_FILE="$TEST_SANDBOX/nope.json"
  run cc_compat_check true
  assert_success
}

# ── Reporting ────────────────────────────────────────────────

@test "cc_compat_report_json reports ok for a tested version" {
  _fake_claude "2.1.220"
  run cc_compat_report_json
  assert_success
  assert_equal "$(printf '%s' "$output" | jq -r .status)" "ok"
}

@test "cc_compat_report_json reports unsupported below the minimum" {
  _fake_claude "1.0.0"
  run cc_compat_report_json
  assert_success
  assert_equal "$(printf '%s' "$output" | jq -r .status)" "unsupported"
}

@test "cc_compat_report_json reports untested above the tested version" {
  _fake_claude "9.9.9"
  run cc_compat_report_json
  assert_success
  assert_equal "$(printf '%s' "$output" | jq -r .status)" "untested"
}

# ── The contract file itself ─────────────────────────────────

@test "the compatibility contract is valid JSON with the fields forge reads" {
  run jq -e '.min_claude_code and .tested_claude_code and .requires.cli_verbs' \
    "$SCRIPT_DIR/templates/cc-compat.json"
  assert_success
}

@test "every hook event forge writes is declared as required" {
  local declared event
  declared=$(jq -r '.requires.hook_events[]' "$SCRIPT_DIR/templates/cc-compat.json" | sort)
  while IFS= read -r event; do
    [ -n "$event" ] || continue
    printf '%s\n' "$declared" | grep -qx "$event" \
      || { echo "settings.json writes hook event '$event' but cc-compat.json does not require it" >&2; return 1; }
  done < <(jq -r '.hooks | keys[]' "$SCRIPT_DIR/templates/settings.json")
}

@test "every CLI verb forge calls is declared as required" {
  # Guards against a new `claude ...` call being added without being declared,
  # which is how the plugins-add breakage went unnoticed.
  local declared
  declared=$(jq -r '.requires.cli_verbs[]' "$SCRIPT_DIR/templates/cc-compat.json")
  grep -qF "plugin install" <<< "$declared"
  grep -qF "plugin marketplace add" <<< "$declared"
  grep -qF "plugin marketplace list" <<< "$declared"
}
