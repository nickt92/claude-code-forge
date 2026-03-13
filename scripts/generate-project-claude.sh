#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Generate Project CLAUDE.md — Brownfield Project Onboarding
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Analyzes an existing codebase and generates a comprehensive
# project-level CLAUDE.md through Claude Code.
#
# Usage:
#   cd /path/to/your-project
#   ~/.claude/scripts/generate-project-claude.sh
#
# What it does:
#   1. Gathers codebase context (structure, deps, configs, git history)
#   2. Launches Claude Code with a specialized prompt
#   3. Claude analyzes the codebase and generates CLAUDE.md
#   4. You review and iterate interactively
#
# Requirements:
#   - Claude Code CLI (claude) installed
#   - Run from the root of the project you want to onboard
#   - jq installed

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[90m'
RST='\033[0m'

info()  { printf "${CYAN}[INFO]${RST} %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${RST}   %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${RST} %s\n" "$1"; }

# ── Pre-flight checks ───────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo -e "${RED}Error: Claude Code CLI not found.${RST}" >&2
  exit 1
fi

if [ ! -d ".git" ]; then
  warn "Not a git repository. Git history analysis will be skipped."
fi

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
CONTEXT_FILE=$(mktemp)
trap "rm -f $CONTEXT_FILE" EXIT

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${BOLD}  Project CLAUDE.md Generator${RST}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  Project: ${CYAN}${PROJECT_NAME}${RST}"
echo -e "  Path:    ${DIM}${PROJECT_DIR}${RST}"
echo ""

# ── Gather codebase context ─────────────────────────────────
info "Gathering codebase context..."

cat > "$CONTEXT_FILE" << 'PROMPT_START'
You are analyzing an existing codebase to generate a comprehensive project-level CLAUDE.md file. This file will be used by Claude Code in every future session with this project.

## Your Task

1. Explore this codebase thoroughly — read the key files listed below, then explore deeper
2. Generate a CLAUDE.md that follows the structure and quality of the reference template below
3. The CLAUDE.md must be SPECIFIC to this project — no generic placeholders
4. Present the CLAUDE.md to me for review. I will iterate with you until it is right.
5. Only write the file when I explicitly approve it.

## What to Analyze

- **Architecture**: Directory structure, service boundaries, how components communicate
- **Tech Stack**: Every framework, library, and tool WITH specific versions (read package.json, requirements.txt, Gemfile, go.mod, etc.)
- **Development**: How to install, run, test, build. What scripts exist. What ports are used.
- **Patterns**: Authentication, state management, API design, error handling, logging
- **Testing**: Where tests live, what framework, any helpers or fixtures, coverage expectations
- **Database**: ORM, migrations, schema location, seed data
- **Deployment**: Platform, CI/CD, environments, production URLs
- **Git Workflow**: Main branch name, branching convention, PR process
- **Gotchas**: Environment variable quirks, build-time vs runtime, port conflicts, common mistakes

## Quality Rules for the Generated CLAUDE.md

- Target under 200 lines. Be concise but comprehensive.
- Use specific versions, not "latest" — read the actual dependency files
- Include real commands the developer runs, not generic ones
- Document patterns that Claude needs to FOLLOW, not just know about
- Include a "Common Pitfalls" section with real issues from the codebase
- If the project uses a monorepo, document the workspace structure and filter commands
- If there are path aliases, document them
- If there are environment variables, point to .env.example or list the critical ones

## Reference Template Structure

```markdown
# CLAUDE.md

## Overview
One paragraph: what is this, what does it do, who uses it.

## Architecture
Directory structure, service communication, key design decisions.

## Tech Stack
Tables with Layer | Technology | Version for each layer.

## Development
### Common Commands
Install, dev, test, build, database commands — the real ones.

### Environment Variables
Where to find them, critical ones to know about.

### Service Ports
What runs where.

## Key Patterns
Authentication, API design, component patterns, state management — whatever is specific to this project.

## Testing
File locations, framework, helpers, coverage targets.

## Git Workflow
Main branch, feature branches, PR target.

## Deployment
Platform, URLs, CI/CD.

## Common Pitfalls
Numbered list of real gotchas.
```

## Codebase Context (gathered automatically)

PROMPT_START

# ── Directory structure (depth 3, excluding common noise) ────
echo "" >> "$CONTEXT_FILE"
echo "### Directory Structure" >> "$CONTEXT_FILE"
echo '```' >> "$CONTEXT_FILE"
if command -v tree >/dev/null 2>&1; then
  tree -L 3 -I 'node_modules|.git|dist|build|.next|__pycache__|.venv|venv|target|.cache|coverage|.turbo|.nuxt' --dirsfirst 2>/dev/null >> "$CONTEXT_FILE" || \
  find . -maxdepth 3 -type d \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' \
    -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/.venv/*' \
    -not -path '*/target/*' -not -path '*/.cache/*' -not -path '*/.turbo/*' \
    | sort >> "$CONTEXT_FILE"
else
  find . -maxdepth 3 -type d \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' \
    -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/.venv/*' \
    -not -path '*/target/*' -not -path '*/.cache/*' -not -path '*/.turbo/*' \
    | sort >> "$CONTEXT_FILE"
fi
echo '```' >> "$CONTEXT_FILE"
ok "Directory structure"

# ── Dependency files ─────────────────────────────────────────
echo "" >> "$CONTEXT_FILE"
echo "### Dependency Files" >> "$CONTEXT_FILE"

for dep_file in package.json requirements.txt Pipfile pyproject.toml Gemfile go.mod \
                Cargo.toml build.gradle pom.xml composer.json pubspec.yaml; do
  # Check root and one level down (for monorepos)
  for found in $(find . -maxdepth 3 -name "$dep_file" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -10); do
    echo "" >> "$CONTEXT_FILE"
    echo "#### $found" >> "$CONTEXT_FILE"
    echo '```' >> "$CONTEXT_FILE"
    head -100 "$found" >> "$CONTEXT_FILE" 2>/dev/null
    echo '```' >> "$CONTEXT_FILE"
  done
done
ok "Dependency files"

# ── Config files ─────────────────────────────────────────────
echo "" >> "$CONTEXT_FILE"
echo "### Configuration Files" >> "$CONTEXT_FILE"

for config_file in tsconfig.json tsconfig*.json .eslintrc* eslint.config* \
                   docker-compose*.yml docker-compose*.yaml Dockerfile* \
                   .github/workflows/*.yml .gitlab-ci.yml Makefile \
                   turbo.json pnpm-workspace.yaml lerna.json nx.json \
                   vite.config* webpack.config* next.config* \
                   render.yaml fly.toml vercel.json netlify.toml \
                   .env.example; do
  for found in $(find . -maxdepth 3 -name "$config_file" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -5); do
    echo "" >> "$CONTEXT_FILE"
    echo "#### $found" >> "$CONTEXT_FILE"
    echo '```' >> "$CONTEXT_FILE"
    head -80 "$found" >> "$CONTEXT_FILE" 2>/dev/null
    echo '```' >> "$CONTEXT_FILE"
  done
done
ok "Configuration files"

# ── Existing documentation ───────────────────────────────────
echo "" >> "$CONTEXT_FILE"
echo "### Existing Documentation" >> "$CONTEXT_FILE"

for doc_file in README.md CONTRIBUTING.md docs/README.md; do
  if [ -f "$doc_file" ]; then
    echo "" >> "$CONTEXT_FILE"
    echo "#### $doc_file" >> "$CONTEXT_FILE"
    echo '```' >> "$CONTEXT_FILE"
    head -150 "$doc_file" >> "$CONTEXT_FILE" 2>/dev/null
    echo '```' >> "$CONTEXT_FILE"
  fi
done
ok "Existing documentation"

# ── Git history and conventions ──────────────────────────────
if [ -d ".git" ]; then
  echo "" >> "$CONTEXT_FILE"
  echo "### Git Info" >> "$CONTEXT_FILE"

  echo "" >> "$CONTEXT_FILE"
  echo "#### Current branch" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  git branch --show-current >> "$CONTEXT_FILE" 2>/dev/null || echo "(detached)" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"

  echo "" >> "$CONTEXT_FILE"
  echo "#### Default branch" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' >> "$CONTEXT_FILE" || echo "unknown" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"

  echo "" >> "$CONTEXT_FILE"
  echo "#### Recent commits (last 20 — shows commit message conventions)" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  git log --oneline -20 >> "$CONTEXT_FILE" 2>/dev/null
  echo '```' >> "$CONTEXT_FILE"

  echo "" >> "$CONTEXT_FILE"
  echo "#### Contributors" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  git shortlog -sn --no-merges HEAD 2>/dev/null | head -10 >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"

  ok "Git history"
fi

# ── Test structure ───────────────────────────────────────────
echo "" >> "$CONTEXT_FILE"
echo "### Test Files (sample)" >> "$CONTEXT_FILE"
echo '```' >> "$CONTEXT_FILE"
find . -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*.py" -o -name "*_test.go" \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -30 >> "$CONTEXT_FILE"
echo '```' >> "$CONTEXT_FILE"
ok "Test structure"

# ── Script files ─────────────────────────────────────────────
echo "" >> "$CONTEXT_FILE"
echo "### Scripts" >> "$CONTEXT_FILE"
echo '```' >> "$CONTEXT_FILE"
find . -maxdepth 2 -name "*.sh" -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null >> "$CONTEXT_FILE"
if [ -d "scripts" ]; then
  ls -la scripts/ 2>/dev/null >> "$CONTEXT_FILE"
fi
echo '```' >> "$CONTEXT_FILE"
ok "Scripts"

# ── Existing CLAUDE.md check ────────────────────────────────
if [ -f "CLAUDE.md" ]; then
  echo "" >> "$CONTEXT_FILE"
  echo "### Existing CLAUDE.md (will be replaced)" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  cat "CLAUDE.md" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  warn "Existing CLAUDE.md found — Claude will review and improve it"
fi

# ── Context size ─────────────────────────────────────────────
context_lines=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')
context_size=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')
info "Gathered $context_lines lines ($((context_size / 1024))KB) of codebase context"

# ── Launch Claude Code ───────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Launching Claude Code ━━━${RST}"
echo ""
echo "Claude will now analyze your codebase and generate a CLAUDE.md."
echo "Review the output and iterate until you are satisfied."
echo "Claude will only write the file when you explicitly approve."
echo ""

claude --print "$(<"$CONTEXT_FILE")"