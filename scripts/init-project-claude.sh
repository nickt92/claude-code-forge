#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Init Project CLAUDE.md — Greenfield Project Setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# For new projects that don't have code yet. Walks through
# architectural decisions with you and generates a CLAUDE.md
# that establishes conventions before the first line of code.
#
# Usage:
#   mkdir my-new-project && cd my-new-project && git init
#   ~/.claude/scripts/init-project-claude.sh
#
# What it does:
#   1. Asks you about the project (what, who, constraints)
#   2. Claude proposes tech stack and architecture decisions
#   3. Invokes the architect agent to validate the approach
#   4. Generates a CLAUDE.md that becomes the project's constitution
#   5. You review and iterate before any code is written
#
# Requirements:
#   - Claude Code CLI (claude) installed
#   - Run from the root of your new project

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

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${BOLD}  Project CLAUDE.md Init — Greenfield Setup${RST}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  Project: ${CYAN}${PROJECT_NAME}${RST}"
echo -e "  Path:    ${DIM}${PROJECT_DIR}${RST}"
echo ""

# ── Gather project brief from user ──────────────────────────
echo -e "${BOLD}Tell me about your project.${RST}"
echo -e "${DIM}(Press Enter twice when done)${RST}"
echo ""

echo -e "${CYAN}What are you building? Who is it for? What are the key requirements?${RST}"
echo -e "${DIM}Example: \"A SaaS invoicing platform for freelancers. Multi-tenant, Stripe billing, PDF generation. Must support i18n (EN/FR). Team of 2 devs.\"${RST}"
echo ""

brief=""
empty_count=0
while IFS= read -r line; do
  if [ -z "$line" ]; then
    ((empty_count++))
    [ "$empty_count" -ge 2 ] && break
    brief="${brief}\n"
  else
    empty_count=0
    brief="${brief}${line}\n"
  fi
done

if [ -z "$brief" ]; then
  echo -e "${RED}No project description provided. Exiting.${RST}" >&2
  exit 1
fi

echo ""
echo -e "${CYAN}Any tech stack preferences or constraints?${RST}"
echo -e "${DIM}Example: \"Must use Python/FastAPI. PostgreSQL. Deploy to AWS. React frontend preferred but open to alternatives.\"${RST}"
echo -e "${DIM}(Leave blank if open to recommendations. Press Enter twice when done)${RST}"
echo ""

constraints=""
empty_count=0
while IFS= read -r line; do
  if [ -z "$line" ]; then
    ((empty_count++))
    [ "$empty_count" -ge 2 ] && break
    constraints="${constraints}\n"
  else
    empty_count=0
    constraints="${constraints}${line}\n"
  fi
done

# ── Build the prompt ─────────────────────────────────────────
PROMPT_FILE=$(mktemp)
trap "rm -f $PROMPT_FILE" EXIT

cat > "$PROMPT_FILE" << PROMPT_END
You are helping set up a new (greenfield) project. Your job is to make architectural decisions with the user and generate a comprehensive project-level CLAUDE.md that will govern all future development.

## Project Brief
$(echo -e "$brief")

## Tech Stack Preferences / Constraints
$(echo -e "${constraints:-No specific preferences — recommend based on requirements.}")

## Your Task — Follow This Exact Sequence

### Step 1: Propose Architecture
Based on the brief and constraints, propose:
- **Tech stack** with specific versions (language, framework, database, ORM, frontend, build tools, testing, deployment)
- **Project structure** (directory layout)
- **Key architectural patterns** (monolith vs microservices, API style, auth approach, state management)
- **Development workflow** (package manager, dev server, testing framework, CI/CD)

Present this as a clear proposal and ASK the user if they agree or want changes. Do NOT proceed until they approve.

### Step 2: Invoke Architect Review
Once the user approves the high-level approach, invoke the appropriate domain architect agent (via the Agent tool) to validate:
- Is the tech stack appropriate for the requirements?
- Are there scaling concerns with the chosen architecture?
- Are there security considerations to address early?
- What patterns should be established from day one?

Present the architect's findings to the user.

### Step 3: Generate CLAUDE.md
Once both the user and architect approve, generate a CLAUDE.md file that includes:

1. **Overview** — what the project is, who it's for
2. **Architecture** — directory structure, service communication, key design decisions
3. **Tech Stack** — table with Layer | Technology | Version for every component
4. **Development** — install, dev, test, build, database commands (the REAL ones for the chosen stack)
5. **Environment Variables** — what's needed, where .env.example lives
6. **Service Ports** — what runs where
7. **Key Patterns** — authentication approach, API design, component patterns, error handling, logging
8. **Testing** — framework, file locations, coverage targets, helper patterns
9. **Git Workflow** — main branch, feature branches, PR conventions
10. **Deployment** — target platform, environments, CI/CD approach
11. **Common Pitfalls** — known gotchas for the chosen stack

### Quality Rules for the CLAUDE.md
- Target under 200 lines — be concise but comprehensive
- Use SPECIFIC versions (e.g., "React 19", "Express 5", "PostgreSQL 16") not "latest"
- Include REAL commands for the chosen stack, not generic ones
- Document patterns as instructions Claude should FOLLOW, not just know about
- Every section should be actionable — if Claude reads it, it should know exactly what to do
- The file should evolve as the project grows — note this at the bottom

### Step 4: Write the File
Present the complete CLAUDE.md to the user. Only write it to disk when they explicitly approve. Write it to the project root as CLAUDE.md.

## Important
- This is a CONVERSATION. Ask questions if the brief is ambiguous.
- Do NOT make assumptions about deployment targets, auth providers, or paid services without asking.
- If the user has no stack preference, recommend based on the requirements and team size.
- The CLAUDE.md is the project's constitution — it must be right before any code is written.
PROMPT_END

# ── Launch Claude Code ───────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Launching Claude Code ━━━${RST}"
echo ""
echo "Claude will now help you design the project architecture"
echo "and generate your project CLAUDE.md."
echo ""

claude --print "$(<"$PROMPT_FILE")"