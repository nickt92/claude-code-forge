#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-dashboard — configuration health dashboard
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Scans configured repositories, collects configuration data,
# scores effectiveness, and outputs structured JSON.
#
# Usage:
#   forge dashboard           # JSON to stdout
#   forge dashboard --json    # same (backward compat)

cmd_dashboard() {
  source "$FORGE_SOURCE_DIR/lib/cmd-config.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/collect-global.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/collect-repos.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/score.sh"

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        # No-op for backward compatibility
        ;;
      --help|-h)
        _dashboard_help
        return 0
        ;;
      *)
        fail "Unknown option: $1"
        _dashboard_help
        return 1
        ;;
    esac
    shift
  done

  # ── Read scan config ─────────────────────────────────────
  local scan_path scan_depth
  scan_path=$(_config_get "dashboard.scan_path" 2>/dev/null) || true
  scan_depth=$(_config_get "dashboard.scan_depth" 2>/dev/null) || true
  scan_depth="${scan_depth:-3}"

  # ── Collect data ─────────────────────────────────────────
  local global_json
  global_json=$(collect_global_config)

  local repos_json='[]'
  if [ -n "$scan_path" ] && [ -d "$scan_path" ]; then
    repos_json=$(collect_repos "$scan_path" "$scan_depth")
  fi

  # ── Score ────────────────────────────────────────────────
  local global_score
  global_score=$(score_global "$global_json")

  # Score each repo and attach scores to repo JSON
  local scored_repos_parts=()
  while IFS= read -r repo_data; do
    [ -z "$repo_data" ] && continue
    local repo_score
    repo_score=$(score_repo "$repo_data")
    scored_repos_parts+=("$(echo "$repo_data" | jq -c --argjson s "$repo_score" '. + {score: $s}')")
  done < <(echo "$repos_json" | jq -c '.[]')
  local scored_repos
  if [ ${#scored_repos_parts[@]} -eq 0 ]; then
    scored_repos='[]'
  else
    scored_repos=$(printf '%s\n' "${scored_repos_parts[@]}" | jq -s '.')
  fi

  # ── Assemble and output JSON ─────────────────────────────
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n \
    --argjson global "$global_json" \
    --argjson global_score "$global_score" \
    --argjson repos "$scored_repos" \
    --arg generated_at "$generated_at" \
    '{
      schema_version: 1,
      global: $global,
      global_score: $global_score,
      repos: $repos,
      generated_at: $generated_at
    }'
}

_dashboard_help() {
  printf "\n${_C_BOLD}forge dashboard${_C_RST} — configuration health dashboard\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge dashboard              Output JSON dashboard data\n"
  printf "  forge dashboard --json       Same (backward compat)\n"
  printf "\n${_C_BOLD}Configuration:${_C_RST}\n"
  printf "  forge config set dashboard.scan_path ~/repos   Set scan directory\n"
  printf "  forge config set dashboard.scan_depth 3        Set scan depth\n"
}
