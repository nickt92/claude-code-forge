#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Settings merge identity — forge must be able to update its own hooks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# merge_settings deduplicated hook groups by their command string. That key
# cannot express "same hook, new definition", so once a hook was installed its
# timeout, matcher and `if` filter were frozen forever — the installed entry
# always won. It also cannot express "this group is mine and should now be
# gone", so hooks forge stopped shipping were never removed. A plan-checkpoint
# entry dropped in 1.3.0 is still registered on installed machines.
#
# Identity is the hook script basename, which is stable across definition
# changes and is what forge actually owns.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  export FORGE_SOURCE_DIR="$SCRIPT_DIR"
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/forge-inventory.sh"
  source "$SCRIPT_DIR/lib/settings-merge.sh"
}

teardown() {
  teardown_sandbox
}

_write() { printf '%s' "$2" > "$1"; }

# ── Updating a forge hook in place ───────────────────────────

@test "a changed timeout on a forge hook reaches an existing install" {
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":5}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":9}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq -r '.hooks.PreToolUse[0].hooks[0].timeout' "$TEST_SANDBOX/out.json"
  assert_output "9"
}

@test "an added if filter reaches an existing install" {
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/db-guard.sh"}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/db-guard.sh","if":"Bash(psql:*)"}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq -r '.hooks.PreToolUse[0].hooks[0].if' "$TEST_SANDBOX/out.json"
  assert_output "Bash(psql:*)"
}

@test "a changed matcher reaches an existing install" {
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/secret-filter.sh"}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "Bash|Read", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/secret-filter.sh"}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq -r '.hooks.PostToolUse[0].matcher' "$TEST_SANDBOX/out.json"
  assert_output "Bash|Read"
}

@test "updating a forge hook does not duplicate it" {
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":5}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":9}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq '[.hooks.PreToolUse[] | select([.hooks[].command] | join(",") | contains("command-guard"))] | length' "$TEST_SANDBOX/out.json"
  assert_output "1"
}

# ── Not touching the user's hooks ────────────────────────────

@test "a user hook at a non-forge path is preserved untouched" {
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/scripts/mine.sh","timeout":3}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh"}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"

  run jq -r '[.hooks.PreToolUse[].hooks[0].command] | join(",")' "$TEST_SANDBOX/out.json"
  assert_output --partial "mine.sh"
  assert_output --partial "command-guard.sh"
  run jq -r '[.hooks.PreToolUse[] | select([.hooks[].command] | join(",") | contains("mine.sh"))][0].hooks[0].timeout' "$TEST_SANDBOX/out.json"
  assert_output "3"
}

@test "a user hook pointing at the forge hooks directory is still updated, not duplicated" {
  # Ambiguous by design: forge owns that path, so it is treated as forge's.
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":1}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/command-guard.sh","timeout":5}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq '.hooks.PreToolUse | length' "$TEST_SANDBOX/out.json"
  assert_output "1"
}

# ── Orphan removal ───────────────────────────────────────────

@test "merge leaves an unshipped forge script alone, being unable to tell it from a user script" {
  # Deliberate. ~/.claude/hooks/ may contain scripts the user wrote. Removing
  # by path would destroy them, so merge only claims what the template ships
  # and purge_orphaned_hooks handles the rest using the manifest.
  _write "$TEST_SANDBOX/existing.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "ExitPlanMode", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/plan-checkpoint.sh"}]}
    ]}
  }'
  _write "$TEST_SANDBOX/template.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/secret-filter.sh"}]}
    ]}
  }'

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/out.json"
  run jq -r '[.hooks.PostToolUse[].hooks[0].command] | join(",")' "$TEST_SANDBOX/out.json"
  assert_output --partial "plan-checkpoint"
  assert_output --partial "secret-filter"
}

# ── Orphan removal (manifest-driven) ─────────────────────────

@test "purge removes a hook forge installed but no longer ships" {
  _write "$TEST_SANDBOX/settings.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "ExitPlanMode", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/plan-checkpoint.sh"}]},
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/secret-filter.sh"}]},
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/scripts/mine.sh"}]}
    ]}
  }'

  purge_orphaned_hooks "$TEST_SANDBOX/settings.json" \
    '["plan-checkpoint","secret-filter"]' '["secret-filter"]'

  run jq -r '[.hooks.PostToolUse[].hooks[0].command] | join(",")' "$TEST_SANDBOX/settings.json"
  refute_output --partial "plan-checkpoint"
  assert_output --partial "secret-filter"
  assert_output --partial "mine.sh"
}

@test "purge does not touch a user script forge never installed" {
  _write "$TEST_SANDBOX/settings.json" '{
    "hooks": {"PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/my-own.sh"}]}
    ]}
  }'

  # forge never recorded my-own, so it is not an orphan
  purge_orphaned_hooks "$TEST_SANDBOX/settings.json" '["secret-filter"]' '["secret-filter"]'

  run jq -r '[.hooks.PostToolUse[].hooks[0].command] | join(",")' "$TEST_SANDBOX/settings.json"
  assert_output --partial "my-own.sh"
}

@test "purge is a no-op when nothing is orphaned" {
  _write "$TEST_SANDBOX/settings.json" '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/secret-filter.sh"}]}]}}'
  local before
  before=$(cat "$TEST_SANDBOX/settings.json")
  purge_orphaned_hooks "$TEST_SANDBOX/settings.json" '["secret-filter"]' '["secret-filter"]'
  assert_equal "$(cat "$TEST_SANDBOX/settings.json")" "$before"
}

# ── Idempotence ──────────────────────────────────────────────

@test "merging twice is byte-identical" {
  _write "$TEST_SANDBOX/existing.json" '{"hooks":{"PreToolUse":[]}}'
  cp "$SCRIPT_DIR/templates/settings.json" "$TEST_SANDBOX/template.json"

  merge_settings "$TEST_SANDBOX/existing.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/once.json"
  merge_settings "$TEST_SANDBOX/once.json" "$TEST_SANDBOX/template.json" "$TEST_SANDBOX/twice.json"

  run diff "$TEST_SANDBOX/once.json" "$TEST_SANDBOX/twice.json"
  assert_success
}
