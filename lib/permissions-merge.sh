#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Permissions Merge — add/remove permission presets from settings
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Required commands:
#   jq
#
# Usage:
#   source lib/permissions-merge.sh
#   merge_permissions "/path/to/settings.json" "auto-edit" "/path/to/presets.json"
#   unmerge_permissions "/path/to/settings.json" '["Read","Glob","Write"]'
#
# Merge strategy:
#   - Resolves preset inheritance chain → flat list of permissions
#   - Adds to settings.permissions.allow (union + dedup)
#   - NEVER touches deny rules
#
# Unmerge strategy:
#   - Removes only the specific rules passed (from manifest)
#   - Preserves user-added custom rules

# Resolve a preset's full permission list by walking the inheritance chain.
# Args:
#   $1 — preset name (e.g., "auto-edit")
#   $2 — presets file path
# Outputs: JSON array of all resolved permissions
resolve_preset_permissions() {
  local preset_name="$1"
  local presets_file="$2"

  jq -r --arg name "$preset_name" '
    def resolve(n):
      .presets[n] as $p |
      if $p == null then []
      elif $p.inherits then resolve($p.inherits) + $p.permissions
      else $p.permissions
      end;
    resolve($name) | unique
  ' "$presets_file"
}

# Merge permissions into settings.json from a preset.
# Args:
#   $1 — settings file path
#   $2 — preset name
#   $3 — presets file path
merge_permissions() {
  local settings_file="$1"
  local preset_name="$2"
  local presets_file="$3"

  local resolved
  resolved=$(resolve_preset_permissions "$preset_name" "$presets_file")

  if [ "$resolved" = "[]" ]; then
    fail "Unknown preset: $preset_name"
    return 1
  fi

  # Ensure settings file exists with at least an empty object
  if [ ! -f "$settings_file" ]; then
    echo '{}' > "$settings_file"
  fi

  # Merge: union existing allow + new permissions, dedup, sort
  jq --argjson new_perms "$resolved" '
    .permissions = (
      (.permissions // {}) |
      .allow = ((.allow // []) + $new_perms | unique | sort)
    )
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}

# Remove specific permission rules from settings.json.
# Only removes the exact rules listed — preserves user-added custom rules.
# Args:
#   $1 — settings file path
#   $2 — JSON array of rules to remove
unmerge_permissions() {
  local settings_file="$1"
  local rules_to_remove="$2"

  [ -f "$settings_file" ] || return 0

  jq --argjson remove "$rules_to_remove" '
    if .permissions.allow then
      .permissions.allow = (.permissions.allow | map(select(. as $r | ($remove | index($r)) == null)))
    else .
    end |
    # Clean up empty permissions object
    if (.permissions // {} | .allow // [] | length) == 0 and (.permissions // {} | .deny // null) == null then
      del(.permissions)
    elif (.permissions.allow // [] | length) == 0 then
      del(.permissions.allow)
    else .
    end
  ' "$settings_file" > "${settings_file}.tmp"
  mv "${settings_file}.tmp" "$settings_file"
}
