#!/bin/bash
# cmd-audit — Audit CLAUDE.md quality for a repository
# Runs section coverage, staleness, tech stack alignment, and content quality checks.

cmd_audit() {
  source "$FORGE_SOURCE_DIR/lib/dashboard/audit-claude-md.sh"

  local target_path="."
  local json_output=false
  local fix_mode=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json_output=true
        shift
        ;;
      --fix)
        fix_mode=true
        shift
        ;;
      --help|-h)
        _audit_help
        return 0
        ;;
      -*)
        forge_fail "Unknown option: $1"
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
    forge_fail "Path not found: $target_path"
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

  # Fix mode — auto-fix fixable findings
  if [ "$fix_mode" = true ]; then
    _audit_fix "$audit_json" "$resolved"
  fi
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
    forge_fail "No CLAUDE.md found in $repo_path"
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

  local line_count imperative_ratio
  line_count=$(echo "$audit_json" | jq -r '.quality.line_count // 0')
  imperative_ratio=$(echo "$audit_json" | jq -r '.quality.imperative_ratio // 0')

  kv "Length" "$length_assessment ($line_count lines)"
  if [ "$line_count" -gt 200 ]; then
    warn "Over 200 lines — consider trimming for faster context loading"
  fi
  if [ "$imperative_ratio" -gt 0 ]; then
    kv "Imperative voice" "${imperative_ratio}%"
    if [ "$imperative_ratio" -lt 50 ]; then
      warn "Low imperative ratio — prefer direct instructions (Use, Always, Never)"
    fi
  fi
  if [ "$has_placeholders" = "true" ]; then
    warn "Contains TODO/FIXME/placeholder markers"
  else
    ok "No placeholder markers found"
  fi

  # Hook compatibility
  local hook_missing_count
  hook_missing_count=$(echo "$audit_json" | jq -r '.hook_compat.missing | length' 2>/dev/null || echo 0)
  if [ "$hook_missing_count" -gt 0 ]; then
    local missing_hooks
    missing_hooks=$(echo "$audit_json" | jq -r '.hook_compat.missing | join(", ")')
    warn "Hooks referenced but not installed: $missing_hooks"
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

_audit_fix() {
  local audit_json="$1"
  local repo_path="$2"

  local fixable_count
  fixable_count=$(echo "$audit_json" | jq '[.findings[] | select(.fixable == true)] | length')
  if [ "$fixable_count" -eq 0 ]; then
    info "No auto-fixable findings"
    return 0
  fi

  step "Auto-fix ($fixable_count fixable findings)"

  # Determine target CLAUDE.md
  local claude_md=""
  if [ -f "$repo_path/.claude/CLAUDE.md" ]; then
    claude_md="$repo_path/.claude/CLAUDE.md"
  elif [ -f "$repo_path/CLAUDE.md" ]; then
    claude_md="$repo_path/CLAUDE.md"
  fi

  # Fix: no_claude_md — create minimal CLAUDE.md
  if echo "$audit_json" | jq -e '.findings[] | select(.code == "no_claude_md")' >/dev/null 2>&1; then
    if [ -z "$claude_md" ]; then
      mkdir -p "$repo_path/.claude"
      claude_md="$repo_path/.claude/CLAUDE.md"
      local repo_name
      repo_name=$(basename "$repo_path")
      cat > "$claude_md" <<EOF
# $repo_name

## Overview
<!-- Describe this project -->

## Tech Stack
<!-- List technologies, frameworks, versions -->

## Testing
<!-- Test commands and strategy -->

## Architecture
<!-- Key patterns and structure -->
EOF
      ok "Created $claude_md with scaffold sections"
    fi
  fi

  # Fix: missing sections — append section stubs
  if [ -n "$claude_md" ] && [ -f "$claude_md" ]; then
    local fixed=0
    local missing_sections_tmp
    missing_sections_tmp=$(mktemp)
    # Get missing sections from individual findings or from the sections data
    echo "$audit_json" | jq -r '.findings[] | select(.code == "missing_section") | .section' 2>/dev/null > "$missing_sections_tmp"
    # If low_coverage finding exists, get missing sections from sections data directly
    if [ ! -s "$missing_sections_tmp" ]; then
      echo "$audit_json" | jq -r '.sections.missing[]' 2>/dev/null > "$missing_sections_tmp"
    fi
    while IFS= read -r section; do
      [ -z "$section" ] && continue
      local heading=""
      case "$section" in
        tech-stack)    heading="Tech Stack" ;;
        testing)       heading="Testing" ;;
        architecture)  heading="Architecture" ;;
        error-handling) heading="Error Handling" ;;
        security)      heading="Security" ;;
        conventions)   heading="Conventions" ;;
        deployment)    heading="Deployment" ;;
        performance)   heading="Performance" ;;
        dependencies)  heading="Dependencies" ;;
      esac
      if [ -n "$heading" ]; then
        printf '\n## %s\n<!-- Add %s details -->\n' "$heading" "$(echo "$heading" | tr '[:upper:]' '[:lower:]')" >> "$claude_md"
        ok "Added ## $heading section"
        fixed=$(( fixed + 1 ))
      fi
    done < "$missing_sections_tmp"
    rm -f "$missing_sections_tmp"

    # Fix: tech gaps — append tech mention
    echo "$audit_json" | jq -r '.findings[] | select(.code == "tech_gap") | .detail' 2>/dev/null | while IFS= read -r detail; do
      [ -z "$detail" ] && continue
      local tech
      tech=$(echo "$detail" | awk '{print $1}')
      if [ -n "$tech" ] && ! grep -qi "$tech" "$claude_md" 2>/dev/null; then
        # Find tech-stack section and note it, or append
        ok "Tech gap noted: $tech (add to Tech Stack section manually)"
      fi
    done
  fi
}

_audit_help() {
  printf "\n${_C_BOLD}forge audit${_C_RST} — Audit CLAUDE.md quality\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge audit [path]         Audit CLAUDE.md in path (default: .)\n"
  printf "  forge audit [path] --json  Output structured JSON\n"
  printf "  forge audit [path] --fix   Auto-fix fixable findings\n"
  printf "\n${_C_BOLD}Options:${_C_RST}\n"
  printf "  --json      Output JSON instead of human-readable report\n"
  printf "  --fix       Auto-fix fixable findings (add missing sections)\n"
  printf "  --help, -h  Show this help\n"
  printf "\n${_C_BOLD}Checks:${_C_RST}\n"
  printf "  Section coverage   Known section headings present vs expected\n"
  printf "  Staleness          CLAUDE.md age vs repo activity\n"
  printf "  Tech stack         Detected tech vs mentioned in config\n"
  printf "  Content quality    Length, line count, imperative language ratio\n"
  printf "  Hook compatibility Referenced hooks vs installed hooks\n"
}
