#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard — collect global ~/.claude/ configuration data
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Produces a JSON blob describing the global forge installation:
# persona, axes, hooks, plugins, rules, version, install date.
#
# Usage:
#   source lib/dashboard/collect-global.sh
#   collect_global_config    # outputs JSON to stdout

# Collect persona and axes from profile.json
_collect_persona() {
  local profile="$CLAUDE_DIR/profile.json"
  if [ -f "$profile" ]; then
    jq '{
      persona: (.persona // "unknown"),
      label: (.label // .persona // "unknown"),
      description: (.description // ""),
      axes: (.axes // {}),
      quality: (.quality // [])
    }' "$profile" 2>/dev/null
  else
    echo '{"persona":"unknown","label":"unknown","description":"","axes":{},"quality":[]}'
  fi
}

# Collect hook status from settings.json
_collect_hooks() {
  local settings="$CLAUDE_DIR/settings.json"
  if [ ! -f "$settings" ]; then
    echo '[]'
    return
  fi

  # Extract all hook commands with their event type and matcher
  jq '[
    .hooks // {} |
    to_entries[] |
    .key as $event |
    .value[] |
    {
      event: $event,
      matcher: (.matcher // ""),
      command: (.hooks[0].command // "unknown"),
      timeout: (.hooks[0].timeout // null),
      name: ((.hooks[0].command // "") | split("/") | last | split(".") | first)
    }
  ]' "$settings" 2>/dev/null || echo '[]'
}

# Collect plugin status from settings.json
_collect_plugins() {
  local settings="$CLAUDE_DIR/settings.json"
  if [ ! -f "$settings" ]; then
    echo '{"group":"unknown","count":0,"plugins":[]}'
    return
  fi

  local group="unknown"
  local manifest="$CLAUDE_DIR/forge-backup/manifest.json"
  if [ -f "$manifest" ]; then
    group=$(jq -r '.plugin_group // "unknown"' "$manifest" 2>/dev/null)
  fi

  local plugins_json
  plugins_json=$(jq '[.enabledPlugins // {} | to_entries[] | select(.value == true) | .key]' "$settings" 2>/dev/null || echo '[]')
  local count
  count=$(echo "$plugins_json" | jq 'length' 2>/dev/null || echo 0)

  jq -n --arg group "$group" --argjson count "$count" --argjson plugins "$plugins_json" \
    '{group: $group, count: $count, plugins: $plugins}'
}

# Collect rules info
_collect_rules() {
  local rules_dir="$CLAUDE_DIR/rules"
  if [ ! -d "$rules_dir" ]; then
    echo '{"count":0,"files":[]}'
    return
  fi

  local files='[]'
  local count=0
  # Guard: check for actual .md files before globbing (avoids zsh no-match errors)
  ls "$rules_dir"/*.md >/dev/null 2>&1 || { jq -n '{count: 0, files: []}'; return; }
  for f in "$rules_dir"/*.md; do
    [ -f "$f" ] || continue
    local name
    name=$(basename "$f" .md)
    files=$(echo "$files" | jq --arg n "$name" '. + [$n]')
    count=$((count + 1))
  done

  jq -n --argjson count "$count" --argjson files "$files" \
    '{count: $count, files: $files}'
}

# Collect version and install metadata from manifest
_collect_install_meta() {
  local manifest="$CLAUDE_DIR/forge-backup/manifest.json"
  if [ -f "$manifest" ]; then
    jq '{
      forge_version: (.forge_version // "unknown"),
      install_timestamp: (.install_timestamp // "unknown"),
      manifest_version: (.manifest_version // 0),
      source_dir: (.source_dir // "unknown")
    }' "$manifest" 2>/dev/null
  else
    echo '{"forge_version":"unknown","install_timestamp":"unknown","manifest_version":0,"source_dir":"unknown"}'
  fi
}

# Check if CLAUDE.md exists and has content
_collect_claude_md_status() {
  local claude_md="$CLAUDE_DIR/CLAUDE.md"
  if [ -f "$claude_md" ]; then
    local lines
    lines=$(wc -l < "$claude_md" | tr -d ' ')
    local size
    size=$(wc -c < "$claude_md" | tr -d ' ')
    jq -n --argjson lines "$lines" --argjson size "$size" \
      '{exists: true, lines: $lines, size: $size}'
  else
    echo '{"exists":false,"lines":0,"size":0}'
  fi
}

# ── Public API ───────────────────────────────────────────────

collect_global_config() {
  local persona hooks plugins rules install_meta claude_md

  persona=$(_collect_persona)
  hooks=$(_collect_hooks)
  plugins=$(_collect_plugins)
  rules=$(_collect_rules)
  install_meta=$(_collect_install_meta)
  claude_md=$(_collect_claude_md_status)

  jq -n \
    --argjson persona "$persona" \
    --argjson hooks "$hooks" \
    --argjson plugins "$plugins" \
    --argjson rules "$rules" \
    --argjson install_meta "$install_meta" \
    --argjson claude_md "$claude_md" \
    '{
      persona: $persona,
      hooks: $hooks,
      plugins: $plugins,
      rules: $rules,
      install: $install_meta,
      claude_md: $claude_md
    }'
}
