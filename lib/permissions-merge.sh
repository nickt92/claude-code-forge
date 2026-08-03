#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Permissions Merge — apply permission presets to settings.json
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/permissions-merge.sh
#   merge_permissions "/path/settings.json" "auto-edit" "/path/presets.json"
#   unmerge_permissions "/path/settings.json" '{"allow":[...],"ask":[...]}'
#
# Schema v2 (templates/permission-presets.json):
#   - allow inherits down the tier chain
#   - ask and deny are GLOBAL and tier-independent: tiers are a trust axis
#     ("I trust Claude more with my codebase"), and losing your AWS credentials
#     is not on that axis. Inheritance is monotonic, so a per-tier deny would
#     also mean higher trust gets MORE denies, which is backwards.
#   - deny is only written when explicitly requested. A permission rule has no
#     forge-override; a false positive blocks work with an error the user
#     cannot clear. Note this is the ONLY reason it is opt-in: deny is honoured
#     under bypassPermissions, so it is the stronger control, not the weaker.
#
# Ownership:
#   forge removes only what it added. Rules the user already had are recorded
#   as "adopted" and survive uninstall and preset changes.
#
# Never removes or rewrites a deny rule forge does not own. lib/manifest.sh
# promised that before forge wrote deny at all; it has to survive the release
# that starts writing it.

# Resolve a preset's allow list by walking the inheritance chain.
# Args:
#   $1 — preset name (e.g., "auto-edit")
#   $2 — presets file path
# Outputs: JSON array of allow rules
resolve_preset_permissions() {
  local preset_name="$1"
  local presets_file="$2"

  jq -c --arg name "$preset_name" '
    def resolve(n):
      .presets[n] as $p |
      if $p == null then []
      elif $p.inherits then resolve($p.inherits) + ($p.allow // [])
      else ($p.allow // [])
      end;
    resolve($name) | unique
  ' "$presets_file"
}

# Resolve one rule bucket for a preset.
# Args:
#   $1 — preset name
#   $2 — presets file path
#   $3 — bucket: allow | ask | deny
# Outputs: JSON array
resolve_preset_rules() {
  local preset_name="$1"
  local presets_file="$2"
  local bucket="$3"

  case "$bucket" in
    allow)
      resolve_preset_permissions "$preset_name" "$presets_file"
      ;;
    ask|deny)
      # Global plus the preset's own, which does NOT inherit. In 2.0 every
      # preset's own ask/deny is empty; the slot exists so a future release can
      # add one without another manifest migration.
      jq -c --arg name "$preset_name" --arg b "$bucket" '
        if .presets[$name] == null then []
        else ((.global[$b] // []) + (.presets[$name][$b] // []) | unique)
        end
      ' "$presets_file"
      ;;
    *)
      echo '[]'
      return 1
      ;;
  esac
}

# The defaultMode a preset wants. Empty when the preset does not express one.
resolve_preset_default_mode() {
  jq -r --arg name "$1" '.presets[$name].default_mode // empty' "$2"
}

# Split desired rules into what forge is actually adding versus what the user
# already had.
#
# forge used to record the whole resolved preset as "what forge added", so a
# user who already had Read or Bash(git status:*) had those claimed by forge —
# and removed on uninstall or a preset change. Only rules forge genuinely
# introduced may be taken away again.
#
# Args:
#   $1 — settings file path
#   $2 — desired allow (JSON array)
#   $3 — desired ask   (JSON array, optional)
#   $4 — desired deny  (JSON array, optional)
# Outputs:
#   {"owned":{"allow":[],"ask":[],"deny":[]},"adopted":{...}}
compute_permission_ownership() {
  local settings_file="$1"
  local want_allow="$2"
  local want_ask="${3:-[]}"
  local want_deny="${4:-[]}"

  local cur='{"allow":[],"ask":[],"deny":[]}'
  if [ -f "$settings_file" ]; then
    cur=$(jq -c '{
      allow: (.permissions.allow // []),
      ask:   (.permissions.ask   // []),
      deny:  (.permissions.deny  // [])
    }' "$settings_file" 2>/dev/null) || cur='{"allow":[],"ask":[],"deny":[]}'
  fi
  [ -n "$cur" ] || cur='{"allow":[],"ask":[],"deny":[]}'

  jq -n -c \
    --argjson cur "$cur" \
    --argjson allow "$want_allow" \
    --argjson ask "$want_ask" \
    --argjson deny "$want_deny" '
    def split($want; $have): {
      owned:   ($want - $have),
      adopted: ($want - ($want - $have))
    };
    (split($allow; $cur.allow)) as $a |
    (split($ask;   $cur.ask))   as $k |
    (split($deny;  $cur.deny))  as $d |
    {
      owned:   { allow: $a.owned,   ask: $k.owned,   deny: $d.owned },
      adopted: { allow: $a.adopted, ask: $k.adopted, deny: $d.adopted }
    }'
}

# Merge a preset into settings.json.
# Args:
#   $1 — settings file path
#   $2 — preset name
#   $3 — presets file path
#   $4 — "true" to also write deny rules (default: false)
merge_permissions() {
  local settings_file="$1"
  local preset_name="$2"
  local presets_file="$3"
  local with_deny="${4:-false}"

  local allow ask deny
  allow=$(resolve_preset_permissions "$preset_name" "$presets_file")

  if [ "$allow" = "[]" ] || [ -z "$allow" ]; then
    forge_fail "Unknown preset: $preset_name"
    return 1
  fi

  ask=$(resolve_preset_rules "$preset_name" "$presets_file" ask)
  if [ "$with_deny" = "true" ]; then
    deny=$(resolve_preset_rules "$preset_name" "$presets_file" deny)
  else
    deny='[]'
  fi

  [ -f "$settings_file" ] || echo '{}' > "$settings_file"

  # Append what is genuinely new rather than `unique`-ing the whole array.
  # jq's unique sorts, which would rewrite the user's hand-ordered list on
  # every install and make a merge/unmerge round trip non-identical.
  jq --argjson allow "$allow" --argjson ask "$ask" --argjson deny "$deny" '
    def add($new): . as $have | $have + ($new - $have);
    .permissions = (
      (.permissions // {})
      | .allow = ((.allow // []) | add($allow))
      | (if ($ask | length) > 0
         then .ask = ((.ask // []) | add($ask))
         else . end)
      | (if ($deny | length) > 0
         then .deny = ((.deny // []) | add($deny))
         else . end)
    )
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}

# Write a preset's defaultMode, but only when it is safe to do so.
#
# Records what was there first. forge writes only when the key is unset or
# still holds the value forge last wrote — otherwise the user changed it by
# hand and forge has no business clobbering it.
#
# Args:
#   $1 — settings file path
#   $2 — desired mode
#   $3 — the mode forge last wrote ("" if never)
# Returns: 0 written, 1 skipped (caller warns), 2 nothing to do
merge_default_mode() {
  local settings_file="$1"
  local desired="$2"
  local previously_written="${3:-}"

  [ -n "$desired" ] || return 2
  [ -f "$settings_file" ] || echo '{}' > "$settings_file"

  local current
  current=$(jq -r '.permissions.defaultMode // empty' "$settings_file" 2>/dev/null)

  # "default" is what an unset key already means, so writing it is a visible
  # mutation with no effect. Skip it when the key is absent, and delete it when
  # forge is the one who put a non-default value there.
  if [ "$desired" = "default" ]; then
    if [ -z "$current" ]; then
      return 2
    fi
    if [ "$current" = "$previously_written" ]; then
      jq 'del(.permissions.defaultMode)
          | if (.permissions | length) == 0 then del(.permissions) else . end' \
        "$settings_file" > "${settings_file}.tmp"
      mv "${settings_file}.tmp" "$settings_file"
      return 0
    fi
  fi

  # The value is already what forge wants, but forge is not the one who put it
  # there. Writing anyway would record `written` for a user-authored setting,
  # and uninstall — which deletes the mode when it still matches what forge
  # wrote — would then throw the user's own choice away. Claim nothing.
  if [ -n "$current" ] && [ "$current" = "$desired" ] \
     && [ "$current" != "$previously_written" ]; then
    return 2
  fi

  if [ -n "$current" ] && [ "$current" != "$previously_written" ]; then
    return 1
  fi

  jq --arg mode "$desired" '
    .permissions = ((.permissions // {}) | .defaultMode = $mode)
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}

# Remove permission rules forge owns from settings.json.
#
# Accepts either the v1 shape (a bare array, allow only) or the v2 shape
# ({"allow":[],"ask":[],"deny":[]}). Manifests written before 2.0 store the
# bare array, and they still have to uninstall cleanly.
#
# Args:
#   $1 — settings file path
#   $2 — owned rules (array or object)
unmerge_permissions() {
  local settings_file="$1"
  local owned="$2"

  [ -f "$settings_file" ] || return 0
  [ -n "$owned" ] || return 0

  jq --argjson owned "$owned" '
    (if ($owned | type) == "array"
     then { allow: $owned, ask: [], deny: [] }
     else { allow: ($owned.allow // []),
            ask:   ($owned.ask   // []),
            deny:  ($owned.deny  // []) }
     end) as $o
    | .permissions = (
        (.permissions // {})
        | (if (.allow | type) == "array"
           then .allow = (.allow - $o.allow) else . end)
        | (if (.ask   | type) == "array"
           then .ask   = (.ask   - $o.ask)   else . end)
        | (if (.deny  | type) == "array"
           then .deny  = (.deny  - $o.deny)  else . end)
      )
    # Drop arrays that are now empty, then the object if nothing is left.
    | .permissions |= with_entries(
        select((.value | type) != "array" or (.value | length) > 0))
    | if (.permissions | length) == 0 then del(.permissions) else . end
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}

# Wrappers Claude Code strips from a command before matching it against a rule.
# Kept in sync with the binary's iae()/z8_(): the first group is stripped for
# every behavior, the second only for deny and ask.
_EXPLAIN_WRAPPERS_ALL='["timeout","time","nice","stdbuf","nohup","command","builtin","noglob","xargs"]'
_EXPLAIN_WRAPPERS_DENYASK='["sudo","doas","su","pkexec","env","watch","strace","ltrace","setsid","ionice","taskset","chrt","flock","script","unshare","nsenter","exec"]'

# Explain which rule decides a command, at which precedence.
#
# Mirrors Claude Code's evaluation order: deny -> ask -> allow, first match
# wins, and its wrapper stripping. It is deliberately NOT a reimplementation of
# the AST matcher — it answers "which of forge's rules is in play", which is
# what people want to know when a command prompts unexpectedly. It reads the
# user-scope settings file only; project and enterprise scopes are merged by
# Claude Code and are not visible here.
#
# Args:
#   $1 — settings file path
#   $2 — command string (without the "Bash(...)" wrapper)
# Outputs: "<behavior>\t<rule>" or "passthrough\t(no rule matched)"
# Returns: non-zero if the settings file could not be evaluated
explain_permission() {
  local settings_file="$1"
  local command="$2"

  [ -f "$settings_file" ] || { printf 'passthrough\t(no settings file)\n'; return 0; }

  jq -r --arg cmd "$command" \
     --argjson wrap_all "$_EXPLAIN_WRAPPERS_ALL" \
     --argjson wrap_da "$_EXPLAIN_WRAPPERS_DENYASK" '
    def rulebody: capture("^Bash\\((?<b>.*)\\)$") | .b;
    def norm: gsub("[ \t]+"; " ") | sub("^ +"; "") | sub(" +$"; "");

    # Peel leading wrapper tokens the same way the matcher does, so
    # `timeout 5 rm -rf /` is explained by the rule that really decides it.
    def strip($wrappers):
      def peel:
        . as $c
        | ($c | split(" ")) as $t
        | if ($t | length) > 1 and ($wrappers | index($t[0]))
          then ($t[1:] | join(" ")
                | sub("^(?<n>[0-9]+(\\.[0-9]+)?[smhd]?) "; "")
                | sub("^-[A-Za-z] "; "")) | peel
          else $c
          end;
      peel;

    def matches($c):
      . as $rule
      | (try ($rule | rulebody) catch null) as $body
      | if $body == null then false
        elif ($body | endswith(":*")) then
          ($body[0:-2] | norm) as $p
          | ($c == $p or ($c | startswith($p + " ")))
        elif ($body | test("\\*")) then
          # One extra backslash: in jq "\\(" is an escaped backslash followed by
          # a literal "(", not an interpolation. "\\\(.m)" is the interpolation.
          ($body | norm
            | gsub("(?<m>[.+?^${}()|\\[\\]\\\\])"; "\\\(.m)")
            | gsub("\\*"; ".*")) as $re
          | ($c | test("^" + $re + "$"))
        else ($c == ($body | norm))
        end;

    ($cmd | norm) as $raw
    | ($raw | strip($wrap_all)) as $c_allow
    | ($raw | strip($wrap_all + $wrap_da)) as $c_denyask
    | [ (.permissions.deny  // [])[] | select(matches($c_denyask) or matches($raw)) | "deny\t" + . ]
    + [ (.permissions.ask   // [])[] | select(matches($c_denyask) or matches($raw)) | "ask\t"  + . ]
    + [ (.permissions.allow // [])[]
        | select(matches($c_allow) or matches($raw) or matches("xargs " + $c_allow))
        | "allow\t" + . ]
    | if length == 0 then "passthrough\t(no rule matched)" else .[0] end
  ' "$settings_file"
}

# Merge explicit rule arrays into settings.json.
#
# merge_permissions resolves from the presets file, which means it cannot see
# --except exclusions. Both it and the install path funnel through here so the
# filtered lists are what actually gets written.
#
# Args: $1 settings file, $2 allow, $3 ask, $4 deny (all JSON arrays)
merge_permission_rules() {
  local settings_file="$1" allow="$2" ask="${3:-[]}" deny="${4:-[]}"

  [ -f "$settings_file" ] || echo '{}' > "$settings_file"

  jq --argjson allow "$allow" --argjson ask "$ask" --argjson deny "$deny" '
    def add($new): . as $have | $have + ($new - $have);
    .permissions = (
      (.permissions // {})
      | .allow = ((.allow // []) | add($allow))
      | (if ($ask | length) > 0 then .ask = ((.ask // []) | add($ask)) else . end)
      | (if ($deny | length) > 0 then .deny = ((.deny // []) | add($deny)) else . end)
    )
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}

# Rules that a previous preset auto-approved and this one sends to a prompt.
#
# The naive check — "is this ask rule literally in the old allow array?" — never
# matches anything, because 1.x expressed these as broad wildcards. Bash(gh:*)
# is what made `gh secret set` auto-approved; Bash(gh secret:*) never appeared
# in any allow list. So the test is whether some old allow rule PREFIXES the ask
# rule, which is exactly the coverage relationship that is being withdrawn.
#
# Args: $1 presets file, $2 previous allow array (JSON)
# Outputs: JSON array of rules that lose auto-approval
resolve_newly_prompting() {
  local presets_file="$1"
  local old_allow="${2:-[]}"

  jq -c --argjson old "$old_allow" '
    def body: capture("^(?<t>[A-Za-z]+)\\((?<b>.*)\\)$");
    # Prefix rules yield their prefix; exact rules yield the whole body, so a
    # 1.x Bash(env:*) is correctly seen to have covered the new Bash(env).
    # Wildcard bodies are skipped — subsumption is not decidable by string
    # comparison for those.
    def prefix: (try body catch null)
      | if . == null then null
        elif (.b | endswith(":*")) then {tool: .t, p: (.b[0:-2])}
        elif (.b | test("\\*")) then null
        else {tool: .t, p: .b}
        end;
    ($old | map(prefix) | map(select(. != null))) as $olds
    | [ (.global._newly_prompting // [])[]
        | . as $rule
        | ($rule | prefix) as $rp
        | select(
            ($old | index($rule)) != null
            or ($rp != null and
                ([ $olds[]
                   | . as $o
                   | select($o.tool == $rp.tool
                            and ($rp.p == $o.p
                                 or ($rp.p | startswith($o.p + " ")))) ]
                 | length) > 0))
      ]' "$presets_file"
}
