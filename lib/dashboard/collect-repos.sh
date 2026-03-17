#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard — discover and collect per-repo configuration data
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Scans a configured directory for repositories containing .claude/
# and collects health data for each.
#
# Usage:
#   source lib/dashboard/collect-repos.sh
#   collect_repos "$scan_path" "$scan_depth"   # outputs JSON array to stdout

# Discover repos with .claude/ directories under scan path
_discover_repos() {
  local scan_path="$1"
  local scan_depth="${2:-3}"

  if [ ! -d "$scan_path" ]; then
    return
  fi

  # Find .claude directories, then return their parent (the repo root)
  find "$scan_path" -maxdepth "$scan_depth" -type d -name ".claude" 2>/dev/null | while IFS= read -r claude_dir; do
    local repo_dir
    repo_dir=$(dirname "$claude_dir")
    # Skip the home directory (global config, not a project)
    [ "$repo_dir" = "$HOME" ] && continue
    echo "$repo_dir"
  done | sort -u
}

# Collect data for a single repo
_collect_repo_data() {
  local repo_dir="$1"
  local claude_dir="$repo_dir/.claude"
  local repo_name
  repo_name=$(basename "$repo_dir")

  # CLAUDE.md status
  local has_claude_md=false claude_md_lines=0
  if [ -f "$claude_dir/CLAUDE.md" ]; then
    has_claude_md=true
    claude_md_lines=$(wc -l < "$claude_dir/CLAUDE.md" | tr -d ' ')
  fi

  # Rules
  local rules_count=0 rules_files='[]'
  if [ -d "$claude_dir/rules" ] && ls "$claude_dir/rules"/*.md >/dev/null 2>&1; then
    for f in "$claude_dir/rules"/*.md; do
      [ -f "$f" ] || continue
      local name
      name=$(basename "$f" .md)
      rules_files=$(echo "$rules_files" | jq --arg n "$name" '. + [$n]')
      rules_count=$((rules_count + 1))
    done
  fi

  # Document chain
  local has_project_md=false has_requirements_md=false has_roadmap_md=false
  [ -f "$repo_dir/PROJECT.md" ] && has_project_md=true
  [ -f "$repo_dir/REQUIREMENTS.md" ] && has_requirements_md=true
  [ -f "$repo_dir/ROADMAP.md" ] && has_roadmap_md=true

  # Docchain skip
  local docchain_dismissed=false
  [ -f "$claude_dir/.docchain-skip" ] && docchain_dismissed=true

  # Git status
  local is_git=false git_branch=""
  if [ -d "$repo_dir/.git" ]; then
    is_git=true
    git_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "")
  fi

  # Last modified (most recent file in .claude/)
  local last_modified=""
  local newest_file
  newest_file=$(find "$claude_dir" -type f -newer "$claude_dir" -print 2>/dev/null | head -1)
  if [ -n "$newest_file" ]; then
    last_modified=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$newest_file" 2>/dev/null) \
      || last_modified=$(stat -c "%y" "$newest_file" 2>/dev/null | cut -d. -f1 | tr ' ' 'T') \
      || last_modified=""
  fi
  # Fallback to .claude dir itself
  if [ -z "$last_modified" ]; then
    last_modified=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$claude_dir" 2>/dev/null) \
      || last_modified=$(stat -c "%y" "$claude_dir" 2>/dev/null | cut -d. -f1 | tr ' ' 'T') \
      || last_modified=""
  fi

  # Hooks (project-level)
  local has_hooks=false hooks_count=0
  if [ -d "$claude_dir/hooks" ]; then
    for f in "$claude_dir/hooks"/*.sh; do
      [ -f "$f" ] || continue
      hooks_count=$((hooks_count + 1))
    done
    [ "$hooks_count" -gt 0 ] && has_hooks=true
  fi

  jq -n \
    --arg path "$repo_dir" \
    --arg name "$repo_name" \
    --argjson has_claude_md "$has_claude_md" \
    --argjson claude_md_lines "$claude_md_lines" \
    --argjson rules_count "$rules_count" \
    --argjson rules_files "$rules_files" \
    --argjson has_project_md "$has_project_md" \
    --argjson has_requirements_md "$has_requirements_md" \
    --argjson has_roadmap_md "$has_roadmap_md" \
    --argjson docchain_dismissed "$docchain_dismissed" \
    --argjson is_git "$is_git" \
    --arg git_branch "$git_branch" \
    --argjson has_hooks "$has_hooks" \
    --argjson hooks_count "$hooks_count" \
    '{
      path: $path,
      name: $name,
      claude_md: { exists: $has_claude_md, lines: $claude_md_lines },
      rules: { count: $rules_count, files: $rules_files },
      doc_chain: {
        project_md: $has_project_md,
        requirements_md: $has_requirements_md,
        roadmap_md: $has_roadmap_md,
        dismissed: $docchain_dismissed
      },
      git: { is_repo: $is_git, branch: $git_branch },
      hooks: { present: $has_hooks, count: $hooks_count }
    }'
}

# ── Public API ───────────────────────────────────────────────

collect_repos() {
  local scan_path="$1"
  local scan_depth="${2:-3}"

  if [ -z "$scan_path" ] || [ ! -d "$scan_path" ]; then
    echo '[]'
    return
  fi

  local repos_json='[]'
  while IFS= read -r repo_dir; do
    [ -n "$repo_dir" ] || continue
    local repo_data
    repo_data=$(_collect_repo_data "$repo_dir")
    if [ -n "$repo_data" ]; then
      repos_json=$(echo "$repos_json" | jq --argjson r "$repo_data" '. + [$r]')
    fi
  done < <(_discover_repos "$scan_path" "$scan_depth")

  echo "$repos_json"
}
