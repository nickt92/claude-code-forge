#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge permissions — through the real dispatcher
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The unit tests call _permissions_apply directly, inside a bats test body
# where errexit is off. The dispatcher sets `set -euo pipefail`, and a helper
# returning a documented non-zero status killed the shell between writing
# settings.json and recording ownership of what it had just written — so forge
# disowned 478 rules and uninstall would have left every one behind.
#
# Nothing catches that except running the real binary. These tests do.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  export FORGE_VERSION="1.4.0"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/manifest.sh"
  mkdir -p "$BACKUP_DIR"
  create_test_manifest_v2 "senior-engineer" "$SCRIPT_DIR" "full"
  echo '{}' > "$CLAUDE_DIR/settings.json"
}

teardown() {
  teardown_sandbox
}

_forge() { env HOME="$TEST_SANDBOX" "$SCRIPT_DIR/forge" "$@"; }

# Every preset, because the abort only happened for the two whose default_mode
# is "default" — which is both of the ones a security-conscious user picks.
@test "applying ask-before-changes through the dispatcher succeeds and records ownership" {
  run _forge permissions --preset ask-before-changes --yes
  assert_success
  assert_output --partial "Applied"

  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "ask-before-changes"
  run jq -e '.installed.permissions.schema == 2' "$MANIFEST_FILE"
  assert_success
  run jq -e '(.installed.permissions.owned.allow | length) > 100' "$MANIFEST_FILE"
  assert_success
}

@test "applying auto-edit through the dispatcher succeeds and records ownership" {
  run _forge permissions --preset auto-edit --yes
  assert_success
  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "auto-edit"
}

@test "applying full-autonomy through the dispatcher succeeds and records ownership" {
  run _forge permissions --preset full-autonomy --yes
  assert_success

  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "full-autonomy"
  run jq -e '(.installed.permissions.owned.allow | length) > 400' "$MANIFEST_FILE"
  assert_success
  run jq -e '(.installed.permissions.owned.ask | length) > 100' "$MANIFEST_FILE"
  assert_success
}

@test "settings and manifest agree after applying a preset" {
  # The corruption signature: rules present in settings.json that the manifest
  # does not claim, which uninstall would then leave behind forever.
  _forge permissions --preset full-autonomy --yes >/dev/null

  local in_settings owned
  in_settings=$(jq -c '.permissions.allow' "$CLAUDE_DIR/settings.json")
  owned=$(jq -c '.installed.permissions.owned.allow + .installed.permissions.adopted.allow' \
    "$MANIFEST_FILE")

  run jq -n --argjson s "$in_settings" --argjson o "$owned" -e '($s - $o) | length == 0'
  assert_success
}

@test "a preset round trip through the dispatcher is idempotent" {
  _forge permissions --preset full-autonomy --yes >/dev/null
  cp "$CLAUDE_DIR/settings.json" "$TEST_SANDBOX/first.json"
  _forge permissions --preset full-autonomy --yes >/dev/null

  run diff <(jq -S . "$TEST_SANDBOX/first.json") <(jq -S . "$CLAUDE_DIR/settings.json")
  assert_success
}

@test "--diff writes nothing" {
  local before
  before=$(shasum "$CLAUDE_DIR/settings.json" | cut -d' ' -f1)

  run _forge permissions --preset full-autonomy --diff
  assert_success
  assert_output --partial "Nothing written"

  local after
  after=$(shasum "$CLAUDE_DIR/settings.json" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "a downgrade is refused non-interactively without --yes" {
  _forge permissions --preset full-autonomy --yes >/dev/null

  run _forge permissions --preset ask-before-changes
  assert_failure
  assert_output --partial "Refusing to downgrade"

  # And nothing moved.
  run jq -r '.installed.permissions.preset' "$MANIFEST_FILE"
  assert_output "full-autonomy"
}

@test "--json refuses a downgrade instead of applying it silently" {
  # --json is the desktop app's path and the one a script would take, which is
  # exactly where an unannounced downgrade would go unnoticed.
  _forge permissions --preset full-autonomy --yes >/dev/null

  run _forge permissions --preset ask-before-changes --json
  assert_failure
  run jq -r '.reason' <<< "$output"
  assert_output "downgrade-requires-consent"
}

@test "--except survives into forge install" {
  # _permissions_except promises it takes effect on the next preset apply OR
  # install. install used to re-resolve from the presets file and reinstate the
  # rule the user had opted out of.
  _forge permissions --preset full-autonomy --yes >/dev/null
  _forge permissions --except "Bash(perl:*)" >/dev/null

  run jq -e '.installed.permissions.exceptions | index("Bash(perl:*)") != null' "$MANIFEST_FILE"
  assert_success

  _forge permissions --preset full-autonomy --yes >/dev/null
  run jq -e '.permissions.allow | index("Bash(perl:*)") == null' "$CLAUDE_DIR/settings.json"
  assert_success
}

@test "explain reports the rule that decides a command" {
  _forge permissions --preset full-autonomy --yes >/dev/null

  run _forge permissions --explain "git push --force origin main"
  assert_success
  assert_output --partial "Bash(git push --force:*)"

  run _forge permissions --explain "npm test"
  assert_success
  assert_output --partial "auto-approved"
}

@test "explain survives a user rule containing regex metacharacters" {
  # The escaper emitted a literal \(.m) instead of interpolating, so one rule
  # with a metacharacter in it made jq throw and broke explain for every
  # command — reported as "no rule matches", with exit code 0.
  _forge permissions --preset full-autonomy --yes >/dev/null
  local tmp="$TEST_SANDBOX/s.json"
  jq '.permissions.allow += ["Bash(node scripts/*.js)", "Bash(pnpm --filter=* build)"]' \
    "$CLAUDE_DIR/settings.json" > "$tmp"
  mv "$tmp" "$CLAUDE_DIR/settings.json"

  run _forge permissions --explain "git status --short"
  assert_success
  assert_output --partial "Bash(git status:*)"
}

@test "a malformed settings.json is reported, not a crash" {
  echo 'not json' > "$CLAUDE_DIR/settings.json"

  run _forge permissions
  assert_failure
  assert_output --partial "not valid JSON"
}
