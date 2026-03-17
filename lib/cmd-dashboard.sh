#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-dashboard — generate a local web dashboard
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Scans configured repositories, collects configuration data,
# scores effectiveness, and generates a self-contained HTML file.
#
# Usage:
#   forge dashboard                     # generate dashboard
#   forge dashboard --open              # generate and open in browser
#   forge dashboard --output /tmp/d.html  # custom output path

cmd_dashboard() {
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  source "$FORGE_SOURCE_DIR/lib/cmd-config.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/collect-global.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/collect-repos.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/score.sh"
  source "$FORGE_SOURCE_DIR/lib/dashboard/generate.sh"

  # ── Parse flags ──────────────────────────────────────────
  local output_path="${CLAUDE_DIR}/dashboard/index.html"
  local do_open=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --output|-o)
        shift
        output_path="${1:?--output requires a path}"
        ;;
      --open)
        do_open=true
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

  banner "Dashboard"

  # ── Read scan config ─────────────────────────────────────
  local scan_path scan_depth
  scan_path=$(_config_get "dashboard.scan_path" 2>/dev/null) || true
  scan_depth=$(_config_get "dashboard.scan_depth" 2>/dev/null) || true
  scan_depth="${scan_depth:-3}"

  if [ -z "$scan_path" ]; then
    warn "No scan path configured"
    info "Run: forge config set dashboard.scan_path ~/repos"
    info "Then re-run: forge dashboard"
    info ""
    info "Generating dashboard with global config only (no repo scanning)..."
  fi

  # ── Collect data ─────────────────────────────────────────
  step "Collecting data"

  local global_json
  global_json=$(collect_global_config)
  ok "Global config collected"

  local repos_json='[]'
  if [ -n "$scan_path" ] && [ -d "$scan_path" ]; then
    repos_json=$(collect_repos "$scan_path" "$scan_depth")
    local repo_count
    repo_count=$(echo "$repos_json" | jq 'length')
    ok "$repo_count repositories found"
  fi

  # ── Score ────────────────────────────────────────────────
  step "Computing scores"

  local global_score
  global_score=$(score_global "$global_json")
  ok "Global score: $(echo "$global_score" | jq -r '.total') ($(echo "$global_score" | jq -r '.grade'))"

  # Score each repo and attach scores to repo JSON
  local scored_repos='[]'
  local i=0
  local total_repos
  total_repos=$(echo "$repos_json" | jq 'length')
  while [ "$i" -lt "$total_repos" ]; do
    local repo_data
    repo_data=$(echo "$repos_json" | jq ".[$i]")
    local repo_score
    repo_score=$(score_repo "$repo_data")
    repo_data=$(echo "$repo_data" | jq --argjson s "$repo_score" '. + {score: $s}')
    scored_repos=$(echo "$scored_repos" | jq --argjson r "$repo_data" '. + [$r]')
    i=$((i + 1))
  done

  # ── Assemble final JSON ──────────────────────────────────
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local dashboard_json
  dashboard_json=$(jq -n \
    --argjson global "$global_json" \
    --argjson global_score "$global_score" \
    --argjson repos "$scored_repos" \
    --arg generated_at "$generated_at" \
    '{
      global: $global,
      global_score: $global_score,
      repos: $repos,
      generated_at: $generated_at
    }')

  # ── Generate HTML ────────────────────────────────────────
  step "Generating dashboard"

  generate_dashboard "$dashboard_json" "$output_path"
  ok "Dashboard written to $output_path"

  # ── Open in browser ──────────────────────────────────────
  if [ "$do_open" = true ]; then
    if open_browser "$output_path"; then
      ok "Opened in browser"
    else
      warn "Could not open browser — open manually: $output_path"
    fi
  else
    info "Open with: forge dashboard --open"
    info "Or open directly: $output_path"
  fi
}

_dashboard_help() {
  printf "\n${_C_BOLD}forge dashboard${_C_RST} — generate configuration dashboard\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge dashboard                       Generate dashboard\n"
  printf "  forge dashboard --open                Generate and open in browser\n"
  printf "  forge dashboard --output path.html    Custom output path\n"
  printf "\n${_C_BOLD}Configuration:${_C_RST}\n"
  printf "  forge config set dashboard.scan_path ~/repos   Set scan directory\n"
  printf "  forge config set dashboard.scan_depth 3        Set scan depth\n"
  printf "\n${_C_BOLD}Output:${_C_RST}\n"
  printf "  Default: ~/.claude/dashboard/index.html\n"
  printf "  Self-contained HTML — no external dependencies, works offline.\n"
}
