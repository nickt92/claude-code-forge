#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Settings Unmerge — removes forge additions from settings.json
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Inverse of lib/settings-merge.sh. Restores user's original
# settings while preserving any post-install user additions.
#
# Required commands:
#   jq
#
# Usage:
#   source lib/settings-unmerge.sh
#   unmerge_settings "/path/to/current.json" "/path/to/backup.json" "$forge_additions_json"
#
# Unmerge strategy:
#   With backup:
#     - Start from backup as base
#     - Add back user hooks added post-install (not in forge additions)
#     - Restore backup plugins + user post-install plugins (not forge)
#     - Remove forge top-level keys unless they were in backup
#   Without backup:
#     - Start from current
#     - Remove forge hooks by command match
#     - Remove forge plugins by key
#     - Remove forge top-level keys

# Unmerge settings.json — restore user's original + preserve post-install additions.
# Args:
#   $1 — current settings.json path
#   $2 — backup settings.json path (may not exist)
#   $3 — forge additions JSON blob (from manifest .installed.settings_additions)
unmerge_settings() {
  local current="$1"
  local backup="$2"
  local forge_additions="$3"

  [ -f "$current" ] || return 0

  if [ -f "$backup" ]; then
    # Start from backup, then add any user post-install additions
    jq -n \
      --slurpfile cur "$current" \
      --slurpfile bak "$backup" \
      --argjson forge "$forge_additions" \
      '
      ($cur[0] // {}) as $c |
      ($bak[0] // {}) as $b |
      # Start with backup as base
      $b |
      # Add back any user hooks added post-install (not in forge additions)
      .hooks = (
        ($b.hooks // {}) as $bh |
        ($c.hooks // {}) as $ch |
        ($forge.hooks // {}) as $fh |
        # For each event in current hooks
        ($ch | to_entries | map(
          .key as $event |
          .value as $cur_hooks |
          ($bh[$event] // []) as $bak_hooks |
          ($fh[$event] // []) as $forge_hooks |
          # Keep: backup hooks + user post-install hooks (not in forge)
          {
            key: $event,
            value: (
              $bak_hooks + (
                $cur_hooks | map(
                  select(
                    .hooks[0].command as $cmd |
                    ($bak_hooks | map(.hooks[0].command) | index($cmd)) == null and
                    ($forge_hooks | map(.hooks[0].command) | index($cmd)) == null
                  )
                )
              )
            )
          }
        ) | map(select(.value | length > 0)) | from_entries) as $merged_hooks |
        # Include events from backup that were removed from current
        ($bh | to_entries | map(
          select(.key as $k | $merged_hooks[$k] == null)
        ) | from_entries) + $merged_hooks
      ) |
      # Restore plugins: backup + user post-install (not forge)
      .enabledPlugins = (
        ($b.enabledPlugins // {}) + (
          ($c.enabledPlugins // {}) | to_entries |
          map(select(
            .key as $k |
            ($b.enabledPlugins // {})[$k] == null and
            ($forge.enabledPlugins // {})[$k] == null
          )) | from_entries
        )
      ) |
      # Remove forge-specific top-level keys unless they were in backup
      if $b | has("statusLine") then . else del(.statusLine) end |
      if $b | has("alwaysThinkingEnabled") then . else del(.alwaysThinkingEnabled) end
      ' > "${current}.tmp"
    mv "${current}.tmp" "$current"
  else
    # No backup — remove forge hooks by command match, remove forge plugins by key
    jq -n \
      --slurpfile cur "$current" \
      --argjson forge "$forge_additions" \
      '
      ($cur[0] // {}) as $c |
      $c |
      # Remove forge hooks by command match
      .hooks = (
        ($c.hooks // {}) | to_entries | map(
          .key as $event |
          {
            key: $event,
            value: (
              .value | map(
                select(
                  .hooks[0].command as $cmd |
                  (($forge.hooks[$event] // []) | map(.hooks[0].command) | index($cmd)) == null
                )
              )
            )
          }
        ) | map(select(.value | length > 0)) | from_entries
      ) |
      # Remove forge plugins
      .enabledPlugins = (
        ($c.enabledPlugins // {}) | to_entries |
        map(select(
          .key as $k | ($forge.enabledPlugins // {})[$k] == null
        )) | from_entries
      ) |
      # Remove forge top-level keys
      if ($forge | has("statusLine")) then del(.statusLine) else . end |
      if ($forge | has("alwaysThinkingEnabled")) then del(.alwaysThinkingEnabled) else . end
      ' > "${current}.tmp"
    mv "${current}.tmp" "$current"
  fi
}
