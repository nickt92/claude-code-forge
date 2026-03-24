#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-analyze — gather codebase context as structured JSON
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Extracts codebase context (structure, dependencies, configs,
# git history, tests, scripts) and outputs structured JSON.
# Single source of truth for codebase analysis.
#
# Usage:
#   forge analyze /path/to/repo --json
#   forge analyze                          # current directory

cmd_analyze() {
  local target_dir=""
  local json_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge analyze${_C_RST} — Gather codebase context\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge analyze [path] ${_C_BOLD}--json${_C_RST}       ${_C_DIM}Output as JSON${_C_RST}\n"
        printf "  forge analyze                       ${_C_DIM}Analyze current directory${_C_RST}\n"
        printf "\nGathers directory structure, dependencies, configs, git history,\n"
        printf "test files, and scripts for codebase onboarding.\n"
        return 0
        ;;
      --json)
        json_mode=true
        shift
        ;;
      *)
        if [ -z "$target_dir" ]; then
          target_dir="$1"
        else
          fail "Unknown option: $1"
          return 1
        fi
        shift
        ;;
    esac
  done

  target_dir="${target_dir:-$(pwd)}"

  if [ ! -d "$target_dir" ]; then
    fail "Directory does not exist: $target_dir"
    return 1
  fi

  # Resolve to absolute path
  target_dir="$(cd "$target_dir" && pwd)"

  if [ "$json_mode" != true ]; then
    fail "forge analyze requires --json flag"
    echo "Usage: forge analyze [path] --json"
    return 1
  fi

  _analyze_json "$target_dir"
}

_analyze_json() {
  local dir="$1"
  local name
  name="$(basename "$dir")"

  # Gather each section
  local dir_structure
  dir_structure="$(_analyze_directory_structure "$dir")"

  local deps_json
  deps_json="$(_analyze_files "$dir" "dependency" \
    package.json requirements.txt Pipfile pyproject.toml Gemfile go.mod \
    Cargo.toml build.gradle pom.xml composer.json pubspec.yaml Package.swift)"

  local configs_json
  configs_json="$(_analyze_files "$dir" "config" \
    tsconfig.json .eslintrc.json .eslintrc.js eslint.config.js eslint.config.mjs \
    docker-compose.yml docker-compose.yaml Dockerfile \
    Makefile turbo.json pnpm-workspace.yaml lerna.json nx.json \
    vite.config.ts vite.config.js webpack.config.js next.config.js next.config.mjs \
    render.yaml fly.toml vercel.json netlify.toml .env.example)"

  local docs_json
  docs_json="$(_analyze_files "$dir" "doc" README.md CONTRIBUTING.md)"

  local git_json
  git_json="$(_analyze_git "$dir")"

  local test_files_json
  test_files_json="$(_analyze_test_files "$dir")"

  local scripts_json
  scripts_json="$(_analyze_scripts "$dir")"

  local claude_md_file
  claude_md_file="$(mktemp)"
  if [ -f "$dir/.claude/CLAUDE.md" ]; then
    head -500 "$dir/.claude/CLAUDE.md" > "$claude_md_file" 2>/dev/null
  elif [ -f "$dir/CLAUDE.md" ]; then
    head -500 "$dir/CLAUDE.md" > "$claude_md_file" 2>/dev/null
  fi

  # CI/CD workflows
  local ci_configs_json
  ci_configs_json="$(_analyze_ci "$dir")"

  # Write dir_structure to file for rawfile handling
  local dir_structure_file
  dir_structure_file="$(mktemp)"
  echo "$dir_structure" > "$dir_structure_file"

  # Build final JSON
  local has_claude_md=false
  if [ -s "$claude_md_file" ]; then
    has_claude_md=true
  fi

  if [ "$has_claude_md" = true ]; then
    jq -n \
      --arg path "$dir" \
      --arg name "$name" \
      --rawfile dir_structure "$dir_structure_file" \
      --argjson dependencies "$deps_json" \
      --argjson configs "$configs_json" \
      --argjson documentation "$docs_json" \
      --argjson git "$git_json" \
      --argjson test_files "$test_files_json" \
      --argjson scripts "$scripts_json" \
      --rawfile existing_claude_md "$claude_md_file" \
      --argjson ci_configs "$ci_configs_json" \
      '{
        path: $path,
        name: $name,
        directory_structure: $dir_structure,
        dependencies: $dependencies,
        configs: $configs,
        documentation: $documentation,
        git: $git,
        test_files: $test_files,
        scripts: $scripts,
        existing_claude_md: $existing_claude_md,
        ci_configs: $ci_configs
      }'
  else
    jq -n \
      --arg path "$dir" \
      --arg name "$name" \
      --rawfile dir_structure "$dir_structure_file" \
      --argjson dependencies "$deps_json" \
      --argjson configs "$configs_json" \
      --argjson documentation "$docs_json" \
      --argjson git "$git_json" \
      --argjson test_files "$test_files_json" \
      --argjson scripts "$scripts_json" \
      --argjson ci_configs "$ci_configs_json" \
      '{
        path: $path,
        name: $name,
        directory_structure: $dir_structure,
        dependencies: $dependencies,
        configs: $configs,
        documentation: $documentation,
        git: $git,
        test_files: $test_files,
        scripts: $scripts,
        existing_claude_md: null,
        ci_configs: $ci_configs
      }'
  fi

  rm -f "$claude_md_file" "$dir_structure_file"
}

# ── Directory Structure ─────────────────────────────────────

_analyze_directory_structure() {
  local dir="$1"
  (
    cd "$dir" || exit
    if command -v tree >/dev/null 2>&1; then
      tree -L 3 -I 'node_modules|.git|dist|build|.next|__pycache__|.venv|venv|target|.cache|coverage|.turbo|.nuxt|.svelte-kit' --dirsfirst 2>/dev/null || \
      find . -maxdepth 3 -type d \
        -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' \
        -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/.venv/*' \
        -not -path '*/target/*' -not -path '*/.cache/*' -not -path '*/.turbo/*' \
        2>/dev/null | sort
    else
      find . -maxdepth 3 -type d \
        -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' \
        -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/.venv/*' \
        -not -path '*/target/*' -not -path '*/.cache/*' -not -path '*/.turbo/*' \
        2>/dev/null | sort
    fi
  )
}

# ── File Content Gatherer ───────────────────────────────────

_analyze_files() {
  local dir="$1"
  local kind="$2"
  shift 2

  local tmpfile rel_path content_file
  tmpfile="$(mktemp)"
  echo "[]" > "$tmpfile"

  for filename in "$@"; do
    while IFS= read -r found; do
      [ -z "$found" ] && continue
      rel_path="${found#$dir/}"
      content_file="$(mktemp)"
      head -100 "$found" > "$content_file" 2>/dev/null
      jq --arg file "$rel_path" --rawfile content "$content_file" \
        '. + [{"file": $file, "content": $content}]' "$tmpfile" > "${tmpfile}.new"
      mv "${tmpfile}.new" "$tmpfile"
      rm -f "$content_file"
    done < <(find "$dir" -maxdepth 3 -name "$filename" \
      -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -10)
  done

  cat "$tmpfile"
  rm -f "$tmpfile"
}

# ── CI/CD Configs ───────────────────────────────────────────

_analyze_ci() {
  local dir="$1"
  local tmpfile rel_path content_file
  tmpfile="$(mktemp)"
  echo "[]" > "$tmpfile"

  # GitHub Actions
  if [ -d "$dir/.github/workflows" ]; then
    while IFS= read -r found; do
      [ -z "$found" ] && continue
      rel_path="${found#$dir/}"
      content_file="$(mktemp)"
      head -80 "$found" > "$content_file" 2>/dev/null
      jq --arg file "$rel_path" --rawfile content "$content_file" \
        '. + [{"file": $file, "content": $content}]' "$tmpfile" > "${tmpfile}.new"
      mv "${tmpfile}.new" "$tmpfile"
      rm -f "$content_file"
    done < <(find "$dir/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null | head -5)
  fi

  # GitLab CI
  if [ -f "$dir/.gitlab-ci.yml" ]; then
    content_file="$(mktemp)"
    head -80 "$dir/.gitlab-ci.yml" > "$content_file" 2>/dev/null
    jq --arg file ".gitlab-ci.yml" --rawfile content "$content_file" \
      '. + [{"file": $file, "content": $content}]' "$tmpfile" > "${tmpfile}.new"
    mv "${tmpfile}.new" "$tmpfile"
    rm -f "$content_file"
  fi

  cat "$tmpfile"
  rm -f "$tmpfile"
}

# ── Git Info ────────────────────────────────────────────────

_analyze_git() {
  local dir="$1"

  if [ ! -d "$dir/.git" ]; then
    jq -n '{
      is_repo: false,
      branch: null,
      default_branch: null,
      recent_commits: [],
      contributors: []
    }'
    return
  fi

  (
    cd "$dir" || exit

    local branch
    branch="$(git branch --show-current 2>/dev/null || echo "")"

    local default_branch
    default_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")"

    local commits_json="[]"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      commits_json=$(echo "$commits_json" | jq --arg c "$line" '. + [$c]')
    done < <(git log --oneline -20 2>/dev/null)

    local contributors_json="[]"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local trimmed
      trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
      contributors_json=$(echo "$contributors_json" | jq --arg c "$trimmed" '. + [$c]')
    done < <(git shortlog -sn --no-merges HEAD 2>/dev/null | head -10)

    jq -n \
      --argjson is_repo true \
      --arg branch "$branch" \
      --arg default_branch "$default_branch" \
      --argjson recent_commits "$commits_json" \
      --argjson contributors "$contributors_json" \
      '{
        is_repo: $is_repo,
        branch: $branch,
        default_branch: (if $default_branch == "" then null else $default_branch end),
        recent_commits: $recent_commits,
        contributors: $contributors
      }'
  )
}

# ── Test Files ──────────────────────────────────────────────

_analyze_test_files() {
  local dir="$1"
  local result="[]"
  local rel_path

  while IFS= read -r found; do
    [ -z "$found" ] && continue
    rel_path="${found#$dir/}"
    result=$(echo "$result" | jq --arg f "$rel_path" '. + [$f]')
  done < <(find "$dir" -type f \
    \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*.py" -o -name "*_test.go" \
       -o -name "*Tests.swift" -o -name "*Test.java" -o -name "*_test.rb" \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' \
    -not -path '*/build/*' -not -path '*/.cache/*' \
    2>/dev/null | head -30)

  echo "$result"
}

# ── Scripts ─────────────────────────────────────────────────

_analyze_scripts() {
  local dir="$1"
  local result="[]"
  local rel_path

  while IFS= read -r found; do
    [ -z "$found" ] && continue
    rel_path="${found#$dir/}"
    result=$(echo "$result" | jq --arg f "$rel_path" '. + [$f]')
  done < <(find "$dir" -maxdepth 2 -name "*.sh" \
    -not -path '*/.git/*' -not -path '*/node_modules/*' \
    2>/dev/null | head -20)

  echo "$result"
}
