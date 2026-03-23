#!/bin/bash
# cmd-audit — Audit CLAUDE.md quality for a repository
# Runs section coverage, staleness, tech stack alignment, and content quality checks.

cmd_audit() {
  source "$FORGE_SOURCE_DIR/lib/dashboard/audit-claude-md.sh"

  local target_path="."
  local json_output=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json_output=true
        shift
        ;;
      --help|-h)
        _audit_help
        return 0
        ;;
      -*)
        fail "Unknown option: $1"
        return 1
        ;;
      *)
        target_path="$1"
        shift
        ;;
    esac
  done

  # Resolve path
  local resolved
  resolved=$(cd "$target_path" 2>/dev/null && pwd)
  if [ -z "$resolved" ] || [ ! -d "$resolved" ]; then
    fail "Path not found: $target_path"
    return 1
  fi

  # Run audit
  local audit_json
  audit_json=$(audit_claude_md "$resolved")

  if [ "$json_output" = true ]; then
    echo "$audit_json"
    return 0
  fi

  # Human-readable output
  _audit_render "$audit_json" "$resolved"
}

_audit_render() {
  local audit_json="$1"
  local repo_path="$2"
  local repo_name
  repo_name=$(basename "$repo_path")

  banner "CLAUDE.md Audit: $repo_name"

  local has_claude_md lines
  has_claude_md=$(echo "$audit_json" | jq -r '.has_claude_md')
  lines=$(echo "$audit_json" | jq -r '.lines')

  if [ "$has_claude_md" = "false" ]; then
    fail "No CLAUDE.md found in $repo_path"
    info "Checked: $repo_path/CLAUDE.md and $repo_path/.claude/CLAUDE.md"
    info "Run 'forge init' in the repo to create one"
    return 0
  fi

  # Show which locations were found
  local locations
  locations=$(echo "$audit_json" | jq -r '.locations // [] | .[]' 2>/dev/null)
  if [ -n "$locations" ]; then
    while IFS= read -r loc; do
      ok "Found: $loc"
    done <<< "$locations"
    info "Combined: $lines lines"
  else
    ok "CLAUDE.md found ($lines lines)"
  fi

  # Section coverage
  step "Section Coverage"
  local coverage found_count missing_count
  coverage=$(echo "$audit_json" | jq -r '.sections.coverage')
  found_count=$(echo "$audit_json" | jq -r '.sections.found | length')
  missing_count=$(echo "$audit_json" | jq -r '.sections.missing | length')

  kv "Coverage" "${coverage}% ($found_count found, $missing_count missing)"

  if [ "$found_count" -gt 0 ]; then
    echo "$audit_json" | jq -r '.sections.found[]' | while IFS= read -r section; do
      printf "  ${_C_GREEN}✓${_C_RST} %s\n" "$section"
    done
  fi
  if [ "$missing_count" -gt 0 ]; then
    echo "$audit_json" | jq -r '.sections.missing[]' | while IFS= read -r section; do
      printf "  ${_C_YELLOW}✗${_C_RST} %s\n" "$section"
    done
  fi

  # Staleness
  step "Staleness"
  local claude_md_days repo_days is_stale
  claude_md_days=$(echo "$audit_json" | jq -r '.staleness.claude_md_days')
  repo_days=$(echo "$audit_json" | jq -r '.staleness.repo_days')
  is_stale=$(echo "$audit_json" | jq -r '.staleness.stale')

  if [ "$claude_md_days" -ge 0 ]; then
    kv "CLAUDE.md age" "${claude_md_days} days"
  fi
  if [ "$repo_days" -ge 0 ]; then
    kv "Repo activity" "${repo_days} days ago"
  fi
  if [ "$is_stale" = "true" ]; then
    warn "CLAUDE.md is stale relative to repo activity"
  else
    ok "CLAUDE.md is up to date"
  fi

  # Tech stack
  step "Tech Stack Alignment"
  local detected_count gap_count
  detected_count=$(echo "$audit_json" | jq -r '.tech_stack.detected | length')
  gap_count=$(echo "$audit_json" | jq -r '.tech_stack.gaps | length')

  if [ "$detected_count" -eq 0 ]; then
    info "No tech stack markers detected"
  else
    kv "Detected" "$(echo "$audit_json" | jq -r '.tech_stack.detected | join(", ")')"
    if [ "$gap_count" -gt 0 ]; then
      warn "Not mentioned: $(echo "$audit_json" | jq -r '.tech_stack.gaps | join(", ")')"
    else
      ok "All detected tech mentioned in CLAUDE.md"
    fi
  fi

  # Quality
  step "Content Quality"
  local has_placeholders length_assessment
  has_placeholders=$(echo "$audit_json" | jq -r '.quality.has_placeholders')
  length_assessment=$(echo "$audit_json" | jq -r '.quality.length_assessment')

  kv "Length" "$length_assessment"
  if [ "$has_placeholders" = "true" ]; then
    warn "Contains TODO/FIXME/placeholder markers"
  else
    ok "No placeholder markers found"
  fi

  # Findings summary
  local finding_count
  finding_count=$(echo "$audit_json" | jq '.findings | length')
  if [ "$finding_count" -gt 0 ]; then
    step "Findings ($finding_count)"
    echo "$audit_json" | jq -r '.findings[] | "\(.severity)\t\(.detail)"' | while IFS=$'\t' read -r severity detail; do
      case "$severity" in
        error) printf "  ${_C_RED}✗${_C_RST} %s\n" "$detail" ;;
        warn)  printf "  ${_C_YELLOW}!${_C_RST} %s\n" "$detail" ;;
        info)  printf "  ${_C_DIM}ℹ${_C_RST} %s\n" "$detail" ;;
      esac
    done
  else
    ok "No issues found"
  fi
}

_audit_help() {
  printf "\n${_C_BOLD}forge audit${_C_RST} — Audit CLAUDE.md quality\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge audit [path]         Audit CLAUDE.md in path (default: .)\n"
  printf "  forge audit [path] --json  Output structured JSON\n"
  printf "\n${_C_BOLD}Options:${_C_RST}\n"
  printf "  --json      Output JSON instead of human-readable report\n"
  printf "  --help, -h  Show this help\n"
  printf "\n${_C_BOLD}Checks:${_C_RST}\n"
  printf "  Section coverage   Known section headings present vs expected\n"
  printf "  Staleness          CLAUDE.md age vs repo activity\n"
  printf "  Tech stack         Detected tech vs mentioned in config\n"
  printf "  Content quality    Length assessment, placeholder detection\n"
}
