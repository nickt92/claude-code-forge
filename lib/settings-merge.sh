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
    (.[0] // {}) as $existing |
    (.[1] // {}) as $template |
    ($existing * $template) *
    {
      hooks: (
        ($existing.hooks // {}) as $eh |
        ($template.hooks // {}) as $th |
        ($eh | keys) + ($th | keys) | unique | map(
          { (.): ([$eh[.] // [], $th[.] // []] | add | unique_by(.hooks | map(.command) | sort | join(","))) }
        ) | add // {}
      ),
      enabledPlugins: (($existing.enabledPlugins // {}) * ($template.enabledPlugins // {}))
    }
  ' "$existing" "$template" > "$output"
}
