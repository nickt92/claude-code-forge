#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Settings Merge — additively merges forge settings into existing config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/settings-merge.sh
#   merge_settings "/path/to/existing.json" "/path/to/template.json" "/path/to/output.json"
#
# Merge strategy:
#   - hooks: concatenate arrays per event, deduplicate by command
#   - enabledPlugins: additive object merge (never removes user plugins)
#   - statusLine, alwaysThinkingEnabled: template values win
#   - all other user keys: preserved

merge_settings() {
  local existing="$1"
  local template="$2"
  local output="$3"

  jq -s '
    # The hook scripts this template installs, by basename.
    def script_names:
      [.hooks[]?[]?.hooks[]?.command // ""]
      | map(capture("(?<n>[A-Za-z0-9_-]+)\\.sh") // empty | .n);

    (.[1] // {}) as $tpl_for_names |
    ($tpl_for_names | script_names) as $forge_scripts |

    # A group is forge'"'"'s only if it runs a script THIS TEMPLATE ships. Being
    # inside ~/.claude/hooks/ is not enough: a user who drops their own script
    # in there would have it destroyed, which is a worse bug than the one this
    # is fixing. Scripts forge shipped previously and no longer ships are not
    # matched here — they are left alone, and removed explicitly by
    # purge_orphaned_hooks, which knows from the manifest that forge put them
    # there.
    def forge_owned:
      [.hooks[]?.command // ""]
      | map(capture("(?<n>[A-Za-z0-9_-]+)\\.sh") // empty | .n)
      | any(. as $n | $forge_scripts | index($n) != null);

    (.[0] // {}) as $existing |
    (.[1] // {}) as $template |
    ($existing * $template) *
    {
      hooks: (
        ($existing.hooks // {}) as $eh |
        ($template.hooks // {}) as $th |
        (($eh | keys) + ($th | keys) | unique) as $events |
        reduce $events[] as $event ({};
          . + { ($event): (
            # The user'"'"'s own groups, untouched.
            (($eh[$event] // []) | map(select(forge_owned | not)))
            # Then forge'"'"'s, taken wholesale from the template. Not merged with
            # what is installed: the template is the authority, so a changed
            # timeout, matcher or `if` filter actually lands. Forge-owned groups
            # the template no longer lists are simply not carried over, which is
            # how hooks forge stopped shipping finally get removed.
            + ($th[$event] // [])
          )}
        ) | with_entries(select(.value | length > 0))
      ),
      enabledPlugins: (($existing.enabledPlugins // {}) * ($template.enabledPlugins // {}))
    }
  ' "$existing" "$template" > "$output"
}

# Remove hook groups that run scripts forge installed previously but no longer
# ships. merge_settings deliberately leaves these alone — it cannot tell a
# forge leftover from a script the user wrote into ~/.claude/hooks/ themselves.
# The manifest can: it records which hooks forge installed.
#
# A plan-checkpoint entry dropped in forge 1.3.0 is still registered on
# installed machines because the only cleanup was a hardcoded special case for
# a different hook.
#
# Args:
#   $1 — settings.json path
#   $2 — JSON array of basenames forge previously installed (from the manifest)
#   $3 — JSON array of basenames forge ships now
purge_orphaned_hooks() {
  local settings="$1"
  local previously_owned="$2"
  local currently_shipped="$3"

  [ -f "$settings" ] || return 0

  # Nothing to do — do not rewrite the file. jq would reformat it for no
  # reason, which churns the user's settings and any diff they are watching.
  local orphan_count
  orphan_count=$(jq -n --argjson owned "$previously_owned" --argjson shipped "$currently_shipped" \
    '($owned - $shipped) | length' 2>/dev/null || echo 0)
  [ "${orphan_count:-0}" -gt 0 ] 2>/dev/null || return 0

  local tmp="${settings}.orphan.tmp"
  jq --argjson owned "$previously_owned" --argjson shipped "$currently_shipped" '
    ($owned - $shipped) as $orphans |
    if ($orphans | length) == 0 then .
    else
      .hooks |= (
        with_entries(
          .value |= map(
            select(
              [.hooks[]?.command // ""]
              | map(capture("(?<n>[A-Za-z0-9_-]+)\\.sh") // empty | .n)
              | any(. as $n | $orphans | index($n) != null)
              | not
            )
          )
        )
        | with_entries(select(.value | length > 0))
      )
    end
  ' "$settings" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$settings"
}
