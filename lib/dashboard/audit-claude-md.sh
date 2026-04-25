#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard — CLAUDE.md quality audit engine
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Performs deep analysis of a project's CLAUDE.md configuration:
#   - Section coverage (headings vs expected patterns)
#   - Staleness (CLAUDE.md age vs repo activity)
#   - Tech stack alignment (detected tech vs mentioned in config)
#   - Content quality (length, placeholders)
#
# Usage:
#   source lib/dashboard/audit-claude-md.sh
#   audit_claude_md "$repo_dir"   # outputs JSON audit result to stdout

# Known section heading patterns (matched case-insensitively)
_AUDIT_SECTION_PATTERNS=(
  "tech.stack|stack|technology|technologies"
  "test|testing|tests|test.strategy"
  "architect|architecture|design|patterns"
  "error.handling|errors|error"
  "security"
  "convention|conventions|standards|style|coding.style"
  "deploy|deployment|ci|cd|ci.cd|infrastructure"
  "performance|perf"
  "dependenc|dependencies"
)
_AUDIT_SECTION_NAMES=(
  "tech-stack"
  "testing"
  "architecture"
  "error-handling"
  "security"
  "conventions"
  "deployment"
  "performance"
  "dependencies"
)

# Tech stack detection: file -> tech name
_AUDIT_TECH_FILES=(
  "tsconfig.json:typescript"
  "package.json:nodejs"
  "Cargo.toml:rust"
  "go.mod:go"
  "pyproject.toml:python"
  "requirements.txt:python"
  "Gemfile:ruby"
  "pom.xml:java"
  "build.gradle:kotlin"
  "docker-compose.yml:docker"
  "Dockerfile:docker"
)
_AUDIT_TECH_DIRS=(
  ".github/workflows:github-actions"
)

# ── Section detection ────────────────────────────────────────

_audit_detect_sections() {
  local claude_md="$1"
  local found='[]'
  local missing='[]'
  local total=${#_AUDIT_SECTION_PATTERNS[@]}
  local found_count=0

  # Extract all ## headings from the file
  local headings=""
  if [ -f "$claude_md" ]; then
    headings=$(grep -i '^## ' "$claude_md" 2>/dev/null | sed 's/^## //' | tr '[:upper:]' '[:lower:]')
  fi

  for i in "${!_AUDIT_SECTION_PATTERNS[@]}"; do
    local pattern="${_AUDIT_SECTION_PATTERNS[$i]}"
    local name="${_AUDIT_SECTION_NAMES[$i]}"
    local matched=false

    # Check if any heading matches the pattern
    if [ -n "$headings" ]; then
      if echo "$headings" | grep -qiE "$pattern"; then
        matched=true
      fi
    fi

    if [ "$matched" = true ]; then
      found=$(echo "$found" | jq --arg n "$name" '. + [$n]')
      found_count=$((found_count + 1))
    else
      missing=$(echo "$missing" | jq --arg n "$name" '. + [$n]')
    fi
  done

  local coverage=0
  if [ "$total" -gt 0 ]; then
    coverage=$((found_count * 100 / total))
  fi

  jq -n \
    --argjson found "$found" \
    --argjson missing "$missing" \
    --argjson coverage "$coverage" \
    '{found: $found, missing: $missing, coverage: $coverage}'
}

# ── Staleness detection ──────────────────────────────────────

_audit_staleness() {
  local repo_dir="$1"
  local claude_md="$2"
  local now_epoch
  now_epoch=$(date +%s)

  local claude_md_days=-1
  local repo_days=-1

  # CLAUDE.md last modified via git (preferred)
  if [ -d "$repo_dir/.git" ] && [ -f "$claude_md" ]; then
    local claude_epoch
    claude_epoch=$(git -C "$repo_dir" log -1 --format=%ct -- "$claude_md" 2>/dev/null)
    if [ -n "$claude_epoch" ] && [ "$claude_epoch" -gt 0 ] 2>/dev/null; then
      claude_md_days=$(( (now_epoch - claude_epoch) / 86400 ))
    fi
  fi

  # Fallback to stat if git didn't work
  if [ "$claude_md_days" -eq -1 ] && [ -f "$claude_md" ]; then
    local file_epoch
    if file_epoch=$(stat -f "%m" "$claude_md" 2>/dev/null); then
      claude_md_days=$(( (now_epoch - file_epoch) / 86400 ))
    elif file_epoch=$(stat -c "%Y" "$claude_md" 2>/dev/null); then
      claude_md_days=$(( (now_epoch - file_epoch) / 86400 ))
    fi
  fi

  # Repo last commit
  if [ -d "$repo_dir/.git" ]; then
    local repo_epoch
    repo_epoch=$(git -C "$repo_dir" log -1 --format=%ct 2>/dev/null)
    if [ -n "$repo_epoch" ] && [ "$repo_epoch" -gt 0 ] 2>/dev/null; then
      repo_days=$(( (now_epoch - repo_epoch) / 86400 ))
    fi
  fi

  # Stale if CLAUDE.md is 30+ days older than most recent repo activity
  local is_stale=false
  if [ "$claude_md_days" -ge 0 ] && [ "$repo_days" -ge 0 ]; then
    local gap=$((claude_md_days - repo_days))
    [ "$gap" -ge 30 ] && is_stale=true
  fi

  jq -n \
    --argjson claude_md_days "$claude_md_days" \
    --argjson repo_days "$repo_days" \
    --argjson stale "$is_stale" \
    '{claude_md_days: $claude_md_days, repo_days: $repo_days, stale: $stale}'
}

# ── Tech stack alignment ─────────────────────────────────────

_audit_tech_stack() {
  local repo_dir="$1"
  local claude_md="$2"
  local detected='[]'
  local mentioned='[]'
  local gaps='[]'

  # Detect tech from files
  for entry in "${_AUDIT_TECH_FILES[@]}"; do
    local file="${entry%%:*}"
    local tech="${entry##*:}"
    if [ -f "$repo_dir/$file" ]; then
      # Avoid duplicates
      if ! echo "$detected" | jq -e --arg t "$tech" 'index($t)' >/dev/null 2>&1; then
        detected=$(echo "$detected" | jq --arg t "$tech" '. + [$t]')
      fi
    fi
  done

  # Detect tech from directories
  for entry in "${_AUDIT_TECH_DIRS[@]}"; do
    local dir="${entry%%:*}"
    local tech="${entry##*:}"
    if [ -d "$repo_dir/$dir" ]; then
      if ! echo "$detected" | jq -e --arg t "$tech" 'index($t)' >/dev/null 2>&1; then
        detected=$(echo "$detected" | jq --arg t "$tech" '. + [$t]')
      fi
    fi
  done

  # Check which detected techs are mentioned in CLAUDE.md
  if [ -f "$claude_md" ]; then
    local content
    content=$(tr '[:upper:]' '[:lower:]' < "$claude_md")
    local detected_arr
    detected_arr=$(echo "$detected" | jq -r '.[]')
    while IFS= read -r tech; do
      [ -z "$tech" ] && continue
      if echo "$content" | grep -qi "$tech"; then
        mentioned=$(echo "$mentioned" | jq --arg t "$tech" '. + [$t]')
      else
        gaps=$(echo "$gaps" | jq --arg t "$tech" '. + [$t]')
      fi
    done <<< "$detected_arr"
  else
    gaps="$detected"
  fi

  jq -n \
    --argjson detected "$detected" \
    --argjson mentioned "$mentioned" \
    --argjson gaps "$gaps" \
    '{detected: $detected, mentioned: $mentioned, gaps: $gaps}'
}

# ── Content quality ──────────────────────────────────────────

_audit_quality() {
  local claude_md="$1"
  local has_placeholders=false
  local length_assessment="missing"
  local line_count=0
  local imperative_ratio=0

  if [ -f "$claude_md" ]; then
    line_count=$(wc -l < "$claude_md" | tr -d ' ')

    if [ "$line_count" -lt 10 ]; then
      length_assessment="too-short"
    elif [ "$line_count" -lt 30 ]; then
      length_assessment="minimal"
    elif [ "$line_count" -gt 500 ]; then
      length_assessment="very-long"
    else
      length_assessment="adequate"
    fi

    # Check for placeholder patterns
    if grep -qiE '(TODO|FIXME|PLACEHOLDER|ADD DETAILS|FILL IN|TBD|CHANGEME)' "$claude_md" 2>/dev/null; then
      has_placeholders=true
    fi

    # Imperative vs passive language ratio (sample directive lines)
    local imperative_count=0 passive_count=0
    while IFS= read -r line; do
      # Skip empty lines and headings
      [[ -z "$line" ]] && continue
      [[ "$line" == "#"* ]] && continue
      [[ "$line" == "|"* ]] && continue
      # Count imperative (starts with verb-like words) vs passive patterns
      if echo "$line" | grep -qiE '^\s*-?\s*(Use|Always|Never|Prefer|Avoid|Must|Do not|Run|Set|Add|Create|Check|Ensure|Follow|Keep|Write|Test|Include|Make)'; then
        imperative_count=$(( imperative_count + 1 ))
      fi
      if echo "$line" | grep -qiE '(is used|are used|should be|was created|has been|will be|can be)'; then
        passive_count=$(( passive_count + 1 ))
      fi
    done < "$claude_md"
    local total_voice=$(( imperative_count + passive_count ))
    if [ "$total_voice" -gt 0 ]; then
      imperative_ratio=$(( imperative_count * 100 / total_voice ))
    fi
  fi

  jq -n \
    --argjson has_placeholders "$has_placeholders" \
    --arg length_assessment "$length_assessment" \
    --argjson line_count "$line_count" \
    --argjson imperative_ratio "$imperative_ratio" \
    '{has_placeholders: $has_placeholders, length_assessment: $length_assessment, line_count: $line_count, imperative_ratio: $imperative_ratio}'
}

# ── Hook compatibility ──────────────────────────────────────

_audit_hook_compat() {
  local claude_md="$1"
  local installed_hooks='[]'
  local referenced_hooks='[]'
  local missing_hooks='[]'

  # Find installed hooks
  local hooks_dir="$HOME/.claude/hooks"
  if [ -d "$hooks_dir" ]; then
    for hf in "$hooks_dir"/*.sh; do
      [ -f "$hf" ] || continue
      local hname
      hname=$(basename "$hf" .sh)
      installed_hooks=$(echo "$installed_hooks" | jq --arg h "$hname" '. + [$h]')
    done
  fi

  # Find hook references in CLAUDE.md
  if [ -f "$claude_md" ]; then
    local content
    content=$(cat "$claude_md")
    for hook_name in session-init context-guardian architect-gate commit-validator command-guard secret-filter db-guard backup-transcript forge-update-check; do
      if echo "$content" | grep -qi "$hook_name"; then
        referenced_hooks=$(echo "$referenced_hooks" | jq --arg h "$hook_name" '. + [$h]')
        # Check if referenced but not installed
        if ! echo "$installed_hooks" | jq -e --arg h "$hook_name" 'index($h)' >/dev/null 2>&1; then
          missing_hooks=$(echo "$missing_hooks" | jq --arg h "$hook_name" '. + [$h]')
        fi
      fi
    done
  fi

  jq -n \
    --argjson installed "$installed_hooks" \
    --argjson referenced "$referenced_hooks" \
    --argjson missing "$missing_hooks" \
    '{installed: $installed, referenced: $referenced, missing: $missing}'
}

# ── Findings generator ───────────────────────────────────────

_audit_generate_findings() {
  local sections_json="$1"
  local staleness_json="$2"
  local tech_json="$3"
  local quality_json="$4"
  local has_claude_md="$5"
  local hook_compat_json="${6:-}"

  local findings='[]'

  if [ "$has_claude_md" = "false" ]; then
    findings=$(echo "$findings" | jq '. + [{"severity":"error","code":"no_claude_md","detail":"No CLAUDE.md found","fixable":true}]')
    echo "$findings"
    return
  fi

  # Missing sections
  local missing_count
  missing_count=$(echo "$sections_json" | jq '.missing | length')
  if [ "$missing_count" -gt 0 ]; then
    local missing_names
    missing_names=$(echo "$sections_json" | jq -r '.missing | join(", ")')
    local coverage
    coverage=$(echo "$sections_json" | jq -r '.coverage')
    if [ "$coverage" -lt 30 ]; then
      findings=$(echo "$findings" | jq --arg d "Low section coverage ($coverage%) — missing: $missing_names" \
        '. + [{"severity":"warn","code":"low_coverage","detail":$d,"fixable":true}]')
    else
      # Report individual missing sections
      local section_findings='[]'
      while IFS= read -r section; do
        section_findings=$(echo "$section_findings" | jq --arg d "No $section section found" --arg s "$section" \
          '. + [{"severity":"warn","code":"missing_section","detail":$d,"section":$s,"fixable":true}]')
      done <<< "$(echo "$sections_json" | jq -r '.missing[]')"
      findings=$(echo "$findings" | jq --argjson sf "$section_findings" '. + $sf')
    fi
  fi

  # Staleness
  local is_stale
  is_stale=$(echo "$staleness_json" | jq -r '.stale')
  if [ "$is_stale" = "true" ]; then
    local cmd_days repo_days
    cmd_days=$(echo "$staleness_json" | jq -r '.claude_md_days')
    repo_days=$(echo "$staleness_json" | jq -r '.repo_days')
    findings=$(echo "$findings" | jq --arg d "CLAUDE.md last updated ${cmd_days} days ago, repo active ${repo_days} days ago" \
      '. + [{"severity":"warn","code":"stale","detail":$d,"fixable":false}]')
  fi

  # Tech gaps
  local tech_gaps
  tech_gaps=$(echo "$tech_json" | jq '.gaps | length')
  if [ "$tech_gaps" -gt 0 ]; then
    while IFS= read -r gap; do
      findings=$(echo "$findings" | jq --arg d "$gap detected but not mentioned in CLAUDE.md" \
        '. + [{"severity":"info","code":"tech_gap","detail":$d,"fixable":true}]')
    done <<< "$(echo "$tech_json" | jq -r '.gaps[]')"
  fi

  # Quality issues
  local has_placeholders length_assessment
  has_placeholders=$(echo "$quality_json" | jq -r '.has_placeholders')
  length_assessment=$(echo "$quality_json" | jq -r '.length_assessment')

  if [ "$has_placeholders" = "true" ]; then
    findings=$(echo "$findings" | jq '. + [{"severity":"warn","code":"has_placeholders","detail":"CLAUDE.md contains TODO/FIXME/placeholder markers","fixable":false}]')
  fi
  if [ "$length_assessment" = "too-short" ]; then
    findings=$(echo "$findings" | jq '. + [{"severity":"warn","code":"too_short","detail":"CLAUDE.md is very short (<10 lines)","fixable":false}]')
  fi

  # Line count warning (>200 lines)
  local line_count
  line_count=$(echo "$quality_json" | jq -r '.line_count // 0')
  if [ "$line_count" -gt 200 ]; then
    findings=$(echo "$findings" | jq --arg d "CLAUDE.md is $line_count lines (recommended: under 200)" \
      '. + [{"severity":"warn","code":"too_long","detail":$d,"fixable":false}]')
  fi

  # Imperative language ratio
  local imperative_ratio
  imperative_ratio=$(echo "$quality_json" | jq -r '.imperative_ratio // 0')
  if [ "$imperative_ratio" -gt 0 ] && [ "$imperative_ratio" -lt 50 ]; then
    findings=$(echo "$findings" | jq --arg d "Low imperative language ratio (${imperative_ratio}%) — CLAUDE.md should use direct instructions (Use, Always, Never) not passive descriptions" \
      '. + [{"severity":"info","code":"passive_language","detail":$d,"fixable":false}]')
  fi

  # Hook compatibility
  if [ -n "$hook_compat_json" ]; then
    local missing_hook_count
    missing_hook_count=$(echo "$hook_compat_json" | jq '.missing | length' 2>/dev/null || echo 0)
    if [ "$missing_hook_count" -gt 0 ]; then
      local missing_names
      missing_names=$(echo "$hook_compat_json" | jq -r '.missing | join(", ")')
      findings=$(echo "$findings" | jq --arg d "Hooks referenced in CLAUDE.md but not installed: $missing_names" \
        '. + [{"severity":"warn","code":"missing_hooks","detail":$d,"fixable":false}]')
    fi
  fi

  echo "$findings"
}

# ── File resolution ───────────────────────────────────────────
# Claude Code reads CLAUDE.md from both the repo root and .claude/ directory.
# The audit checks both and combines content for analysis.

_audit_resolve_files() {
  local repo_dir="$1"
  local root_md="$repo_dir/CLAUDE.md"
  local managed_md="$repo_dir/.claude/CLAUDE.md"
  local locations='[]'

  [ -f "$root_md" ] && locations=$(echo "$locations" | jq --arg p "$root_md" '. + [$p]')
  [ -f "$managed_md" ] && locations=$(echo "$locations" | jq --arg p "$managed_md" '. + [$p]')

  echo "$locations"
}

# Create a temporary combined file for content analysis when both exist
_audit_combined_content() {
  local repo_dir="$1"
  local root_md="$repo_dir/CLAUDE.md"
  local managed_md="$repo_dir/.claude/CLAUDE.md"

  if [ -f "$root_md" ] && [ -f "$managed_md" ]; then
    cat "$root_md" "$managed_md"
  elif [ -f "$root_md" ]; then
    cat "$root_md"
  elif [ -f "$managed_md" ]; then
    cat "$managed_md"
  fi
}

# Return the freshest CLAUDE.md path for staleness checking
_audit_freshest_file() {
  local repo_dir="$1"
  local root_md="$repo_dir/CLAUDE.md"
  local managed_md="$repo_dir/.claude/CLAUDE.md"

  if [ -f "$root_md" ] && [ -f "$managed_md" ]; then
    # Pick the more recently modified one
    if [ "$root_md" -nt "$managed_md" ]; then
      echo "$root_md"
    else
      echo "$managed_md"
    fi
  elif [ -f "$root_md" ]; then
    echo "$root_md"
  elif [ -f "$managed_md" ]; then
    echo "$managed_md"
  fi
}

# ── Public API ───────────────────────────────────────────────

audit_claude_md() {
  local repo_dir="$1"
  local root_md="$repo_dir/CLAUDE.md"
  local managed_md="$repo_dir/.claude/CLAUDE.md"

  local has_claude_md=false
  local lines=0
  local locations_json

  locations_json=$(_audit_resolve_files "$repo_dir")

  # Check if any CLAUDE.md exists
  if [ -f "$root_md" ] || [ -f "$managed_md" ]; then
    has_claude_md=true
    # Combined line count
    local root_lines=0 managed_lines=0
    [ -f "$root_md" ] && root_lines=$(wc -l < "$root_md" | tr -d ' ')
    [ -f "$managed_md" ] && managed_lines=$(wc -l < "$managed_md" | tr -d ' ')
    lines=$((root_lines + managed_lines))
  fi

  local sections_json staleness_json tech_json quality_json findings_json hook_compat_json

  if [ "$has_claude_md" = "true" ]; then
    # Use combined content for section detection and tech stack analysis
    local combined_tmp
    combined_tmp=$(mktemp)
    _audit_combined_content "$repo_dir" > "$combined_tmp"

    sections_json=$(_audit_detect_sections "$combined_tmp")
    tech_json=$(_audit_tech_stack "$repo_dir" "$combined_tmp")
    quality_json=$(_audit_quality "$combined_tmp")
    hook_compat_json=$(_audit_hook_compat "$combined_tmp")

    rm -f "$combined_tmp"

    # Use the freshest file for staleness
    local freshest
    freshest=$(_audit_freshest_file "$repo_dir")
    staleness_json=$(_audit_staleness "$repo_dir" "$freshest")
  else
    sections_json='{"found":[],"missing":[],"coverage":0}'
    staleness_json='{"claude_md_days":-1,"repo_days":-1,"stale":false}'
    tech_json='{"detected":[],"mentioned":[],"gaps":[]}'
    quality_json='{"has_placeholders":false,"length_assessment":"missing","line_count":0,"imperative_ratio":0}'
    hook_compat_json='{"installed":[],"referenced":[],"missing":[]}'
  fi

  findings_json=$(_audit_generate_findings "$sections_json" "$staleness_json" "$tech_json" "$quality_json" "$has_claude_md" "$hook_compat_json")

  jq -n \
    --argjson has_claude_md "$has_claude_md" \
    --argjson lines "$lines" \
    --argjson locations "$locations_json" \
    --argjson sections "$sections_json" \
    --argjson staleness "$staleness_json" \
    --argjson tech_stack "$tech_json" \
    --argjson quality "$quality_json" \
    --argjson hook_compat "$hook_compat_json" \
    --argjson findings "$findings_json" \
    '{
      schema_version: 1,
      has_claude_md: $has_claude_md,
      lines: $lines,
      locations: $locations,
      sections: $sections,
      staleness: $staleness,
      tech_stack: $tech_stack,
      quality: $quality,
      hook_compat: $hook_compat,
      findings: $findings
    }'
}
