#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Permission preset schema — build-time invariants
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Claude Code evaluates deny -> ask -> allow and stops at the first match, so
# an overlap between the buckets is not a conflict the platform resolves — it
# is silently dead config. These make each way of getting it wrong a build
# failure rather than something a user discovers when a command stops working.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/permissions-merge.sh"
  PRESETS="$SCRIPT_DIR/templates/permission-presets.json"
}

teardown() {
  teardown_sandbox
}

_resolve() { resolve_preset_rules "$1" "$PRESETS" "$2"; }
_all_allow() { _resolve full-autonomy allow; }

# Almost every test below collects violations and asserts the list is empty,
# which also passes when the resolver returns nothing at all. Renaming the
# preset key .allow back to .permissions — the exact v1-to-v2 regression this
# file exists to catch — produced zero failures until this guard was added.
@test "the resolver actually returns rules (guards every test below)" {
  assert [ "$(_resolve ask-before-changes allow | jq length)" -gt 100 ]
  assert [ "$(_resolve auto-edit allow | jq length)" -gt 150 ]
  assert [ "$(_all_allow | jq length)" -gt 400 ]
  assert [ "$(_resolve full-autonomy ask | jq length)" -gt 100 ]
  assert [ "$(_resolve full-autonomy deny | jq length)" -gt 0 ]
}

@test "presets file is valid JSON and declares schema 2" {
  run jq -e '.schema_version == 2' "$PRESETS"
  assert_success
}

@test "every preset declares a default_mode" {
  run jq -e '[.presets[] | .default_mode] | all(. != null and . != "")' "$PRESETS"
  assert_success
}

@test "no preset auto-approves the bypassPermissions mode" {
  # Writing bypassPermissions would void the allow/ask/deny model this file
  # exists to express, leaving deny as the only thing between the agent and a
  # force push — and deny is itself ignored in that mode.
  run jq -e '[.presets[] | .default_mode] | any(. == "bypassPermissions") | not' "$PRESETS"
  assert_success
}

@test "allow and deny do not overlap" {
  run jq -e --argjson a "$(_all_allow)" '(($a - ($a - .global.deny)) | length) == 0' "$PRESETS"
  assert_success
}

@test "allow and ask do not overlap" {
  run jq -e --argjson a "$(_all_allow)" '(($a - ($a - .global.ask)) | length) == 0' "$PRESETS"
  assert_success
}

@test "ask and deny do not overlap" {
  run jq -e '((.global.ask - (.global.ask - .global.deny)) | length) == 0' "$PRESETS"
  assert_success
}

@test "no ask rule is broader than an allow rule it would silently kill" {
  # Bash(git config:*) in ask would defeat Bash(git config --get:*) in allow,
  # because ask is evaluated first and matches everything the narrower allow
  # rule was meant to permit. This is the failure mode that is invisible in
  # review and only shows up as "why is it asking about that?"
  local offenders
  offenders=$(jq -r --argjson allow "$(_all_allow)" '
    def body: capture("^Bash\\((?<b>.*)\\)$") | .b;
    def prefix: (try body catch null)
      | if . != null and endswith(":*") then .[0:-2] else null end;
    [ .global.ask[] as $ask
      | ($ask | prefix) as $ap
      | select($ap != null)
      | $allow[] as $al
      | ($al | prefix) as $lp
      | select($lp != null and $lp != $ap and ($lp | startswith($ap + " ")))
      | "ask \($ask) kills allow \($al)"
    ] | .[]' "$PRESETS")
  [ -z "$offenders" ] || { echo "$offenders"; return 1; }
}

@test "no universal shell wrapper appears in any allow list" {
  # A wrapper in allow voids every other rule: Bash(bash:*) permits
  # `bash -c '<anything>'`. timeout/nohup/command/xargs are listed too because
  # Claude Code strips them before matching, so allowing them buys nothing
  # while still permitting `timeout 5 rm -rf /`.
  # Derived from the constants permissions-merge.sh feeds the matcher, not
  # retyped: the hand-written copy had drifted by 13 tokens, so Bash(flock:*)
  # in allow would have passed while granting everything flock wraps.
  local banned
  banned=$(jq -n --argjson a "$_EXPLAIN_WRAPPERS_ALL" --argjson b "$_EXPLAIN_WRAPPERS_DENYASK" \
    '$a + $b + ["bash","sh","zsh","fish","ksh","dash","source",".","./","eval"] | unique')
  local hits
  hits=$(jq -r --argjson allow "$(_all_allow)" --argjson banned "$banned" '
    def body: capture("^Bash\\((?<b>.*)\\)$") | .b;
    [ $allow[]
      | . as $r
      | (try ($r | body) catch null) as $b
      | select($b != null and ($b | endswith(":*")))
      | select((($b[0:-2]) | ltrimstr(" ") | rtrimstr(" ")) as $p
               | ($banned | index($p)) != null)
      | $r ] | .[]' "$PRESETS")
  [ -z "$hits" ] || { echo "still allowed: $hits"; return 1; }
}

@test "every rule parses as a known tool and rule kind" {
  local known='["Bash","Read","Edit","Write","Glob","Grep","WebFetch","WebSearch",
                "NotebookEdit","TaskOutput","TaskStop","Agent","SendUserMessage"]'
  local bad
  bad=$(jq -r --argjson allow "$(_all_allow)" --argjson known "$known" '
    ($allow + .global.ask + .global.deny)
    | map(select(
        (capture("^(?<t>[A-Za-z]+)(\\((?<b>.*)\\))?$") // null) as $m
        | $m == null or (($known | index($m.t)) == null)))
    | .[]' "$PRESETS")
  [ -z "$bad" ] || { echo "unknown rule form: $bad"; return 1; }
}

@test "the :* prefix suffix is only used on Bash rules" {
  # Claude Code rejects it elsewhere: "The :* syntax is only for Bash prefix
  # rules."
  local bad
  bad=$(jq -r --argjson allow "$(_all_allow)" '
    ($allow + .global.ask + .global.deny)
    | map(select(endswith(":*)") and (startswith("Bash(") | not)))
    | .[]' "$PRESETS")
  [ -z "$bad" ] || { echo "non-Bash rule using :* — $bad"; return 1; }
}

@test "per-preset ask and deny are empty in 2.0" {
  # The slots exist so a later release can use them without another manifest
  # migration, but deny must stay tier-independent: tiers are a trust axis, and
  # inheritance is monotonic, so per-tier deny would give higher trust more
  # denies.
  run jq -e '[.presets[] | (.ask | length) + (.deny | length)] | add == 0' "$PRESETS"
  assert_success
}

@test "_excluded_from_all_tiers is gone" {
  # It was read by no code for the whole of 1.x while documenting commands as
  # excluded that tier 3 auto-approved.
  run jq -e 'has("_excluded_from_all_tiers") | not' "$PRESETS"
  assert_success
}

@test "the previously-excluded commands are now actually enforced" {
  local must_ask=(
    "Bash(rm:*)" "Bash(sudo:*)" "Bash(chown:*)" "Bash(git push --force:*)"
    "Bash(git reset --hard:*)" "Bash(git clean:*)" "Bash(crontab:*)"
    "Bash(nc:*)" "Bash(ssh:*)" "Bash(kill:*)" "Bash(terraform destroy:*)"
    "Bash(docker system prune:*)"
  )
  for rule in "${must_ask[@]}"; do
    jq -e --arg r "$rule" '(.global.ask | index($r)) != null' "$PRESETS" >/dev/null \
      || { echo "not enforced: $rule"; return 1; }
  done
}

@test "self-protection rules cover re-invoking Claude Code without permissions" {
  # Bash(npx:*) at tier 3 made a single command void the entire model.
  for rule in \
    "Bash(* --dangerously-skip-permissions*)" \
    "Bash(* --permission-mode bypassPermissions*)" \
    "Bash(claude:*)" \
    "Bash(npx @anthropic-ai/claude-code:*)"
  do
    jq -e --arg r "$rule" '(.global.ask | index($r)) != null' "$PRESETS" >/dev/null \
      || { echo "missing self-protection rule: $rule"; return 1; }
  done
}

@test "forge cannot be edited out from under itself without a prompt" {
  for rule in \
    "Edit(~/.claude/settings.json)" \
    "Edit(~/.claude/hooks/**)" \
    "Edit(~/.claude/rules/**)"
  do
    jq -e --arg r "$rule" '(.global.ask | index($r)) != null' "$PRESETS" >/dev/null \
      || { echo "missing self-protection rule: $rule"; return 1; }
  done
}

@test "deny stays small and holds only commands with no legitimate agent use" {
  run jq -e '(.global.deny | length) <= 12' "$PRESETS"
  assert_success
}

@test "_newly_prompting contains no rule that is not actually in ask" {
  # No top-level fallback: resolve_newly_prompting reads .global._newly_prompting
  # only, and a test that tolerates both paths keeps passing when someone moves
  # the key out from under the production reader.
  run jq -e '(.global._newly_prompting - .global.ask) | length == 0' "$PRESETS"
  assert_success
}

@test "_newly_prompting lists every rule 1.x auto-approved that now asks" {
  # The direction that enforces "never silently downgrade an effective
  # permission". Checked against the real 1.x allow list from git, because the
  # rules being withdrawn were expressed as broad wildcards then — Bash(gh:*)
  # is what made `gh secret set` auto-approved; Bash(gh secret:*) never existed.
  # Committed, not read from git history: `git show HEAD:` resolves to the 2.0
  # file the moment this lands, after which the test would skip forever without
  # anyone noticing.
  local v1 v1_allow missing
  v1="$SCRIPT_DIR/test/fixtures/permission-presets-1.x.json"
  assert [ -f "$v1" ]

  v1_allow=$(jq -c 'def r(n): .presets[n] as $p
      | if $p.inherits then r($p.inherits) + $p.permissions else $p.permissions end;
      r("full-autonomy") | unique' "$v1")
  assert [ "$(jq -n --argjson a "$v1_allow" '$a | length')" -gt 300 ]

  # Any ask rule that a 1.x allow prefix covered must be declared.
  missing=$(jq -r --argjson old "$v1_allow" --argjson np "$(jq -c '.global._newly_prompting' "$PRESETS")" '
    def body: capture("^(?<t>[A-Za-z]+)\\((?<b>.*)\\)$");
    def key: (try body catch null)
      | if . == null then null
        elif (.b | endswith(":*")) then {tool: .t, p: (.b[0:-2])}
        elif (.b | test("\\*")) then null
        else {tool: .t, p: .b} end;
    ($old | map(key) | map(select(. != null))) as $olds
    | [ .global.ask[]
        | . as $rule
        | ($rule | key) as $rp
        | select($rp != null)
        | select([ $olds[] | . as $o
                   | select($o.tool == $rp.tool
                            and ($rp.p == $o.p or ($rp.p | startswith($o.p + " ")))) ]
                 | length > 0)
        | select(($np | index($rule)) == null) ]
      | .[]' "$PRESETS")

  [ -z "$missing" ] || {
    echo "withdrawn from 1.x allow but not declared in _newly_prompting:"
    echo "$missing"
    return 1
  }
}

@test "tier 1 does not auto-approve dumping the whole environment" {
  local t1
  t1=$(_resolve ask-before-changes allow)
  for rule in "Bash(env:*)" "Bash(printenv:*)" "Bash(open:*)" "Bash(xdg-open:*)"; do
    echo "$t1" | jq -e --arg r "$rule" '(index($r)) == null' >/dev/null \
      || { echo "tier 1 still allows $rule"; return 1; }
  done
}

@test "tiers stay monotonic: each tier is a superset of the one below" {
  local t1 t2 t3
  t1=$(_resolve ask-before-changes allow)
  t2=$(_resolve auto-edit allow)
  t3=$(_resolve full-autonomy allow)
  jq -n --argjson a "$t1" --argjson b "$t2" -e '($a - $b) | length == 0' >/dev/null \
    || { echo "tier 2 dropped rules from tier 1"; return 1; }
  jq -n --argjson a "$t2" --argjson b "$t3" -e '($a - $b) | length == 0' >/dev/null \
    || { echo "tier 3 dropped rules from tier 2"; return 1; }
}

@test "resolved presets contain no duplicates" {
  for p in ask-before-changes auto-edit full-autonomy; do
    local r
    r=$(_resolve "$p" allow)
    jq -n --argjson x "$r" -e '($x | length) == ($x | unique | length)' >/dev/null \
      || { echo "duplicate rules in $p"; return 1; }
  done
}
