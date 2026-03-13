#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Init Project CLAUDE.md — Greenfield Project Setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Launches an interactive Claude session that walks you through
# setting up a new project. Adapts to the user's persona —
# technical users get architecture details, non-technical users
# get product-focused conversations.
#
# Usage:
#   mkdir my-new-project && cd my-new-project && git init
#   ~/.claude/scripts/init-project-claude.sh
#
# Requirements:
#   - Claude Code CLI (claude) installed
#   - Run from the root of your new project

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[90m'
RST='\033[0m'

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# ── Pre-flight ───────────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo -e "${RED}Claude Code CLI not found.${RST} Install from: https://docs.anthropic.com/en/docs/claude-code" >&2
  exit 1
fi

if [ ! -d ".git" ]; then
  echo -e "This directory isn't a git repo yet."
  read -p "Initialize one here? (Y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    git init
  else
    echo -e "${RED}Cancelled.${RST}" >&2
    exit 1
  fi
fi

# ── Read persona ─────────────────────────────────────────────
PROFILE="$HOME/.claude/profile.json"
DEPTH="engineering"
COMM="expert"
if [ -f "$PROFILE" ] && command -v jq >/dev/null 2>&1; then
  DEPTH=$(jq -r '.axes.depth // "engineering"' "$PROFILE" 2>/dev/null)
  COMM=$(jq -r '.axes.communication // "expert"' "$PROFILE" 2>/dev/null)
fi

# Non-technical: conceptual depth OR plain communication
if [ "$DEPTH" = "conceptual" ] || [ "$COMM" = "plain" ]; then
  PERSONA_MODE="non-technical"
else
  PERSONA_MODE="technical"
fi

# ── Launch ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${BOLD}  Claude Code Forge — New Project Setup${RST}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  Project: ${CYAN}${PROJECT_NAME}${RST}"
echo -e "  Path:    ${DIM}${PROJECT_DIR}${RST}"
echo ""
echo -e "  Starting an interactive session. Tell Claude what you're"
echo -e "  building and it'll handle the rest."
echo ""
echo -e "${DIM}  Tip: Keep it simple. \"We're a law firm, need a website\" is fine.${RST}"
echo ""

# ── Build system prompt based on persona ─────────────────────
if [ "$PERSONA_MODE" = "non-technical" ]; then
  SYSTEM_PROMPT="You are helping set up a brand new project in: ${PROJECT_DIR} (${PROJECT_NAME}).

The user is NOT technical. They are a business owner, executive, or non-coder. Adapt accordingly.

YOUR APPROACH:
1. The user will describe what they want — probably in plain, non-technical terms. That's perfect.
2. Ask about the PRODUCT, not the technology:
   - What does the business do? Who are the customers?
   - What pages or features does the site/app need?
   - What should it feel like? (Professional? Friendly? Luxury?)
   - Are there any competitor sites they like the look of?
   - Do they need a contact form, booking system, or anything interactive?
   - Do they have a domain name? Logo? Brand colors?
3. Make ALL technical decisions yourself. Do NOT ask about frameworks, databases, hosting providers, or any implementation details. Just pick the best options for their needs.
4. When you have enough context, summarize what you're going to build in plain language — what pages, what features, what it'll look like. Ask if that sounds right.
5. Once they approve, make the technical decisions internally, invoke the architect agent to validate, and generate the CLAUDE.md.
6. Present the CLAUDE.md as: \"Here's the project blueprint — this tells me exactly how to build what we discussed. Want me to save it?\"

COMMUNICATION RULES:
- NO technical jargon. No mention of React, Next.js, APIs, databases, TypeScript, or any framework names in conversation.
- Talk about pages, features, design, and user experience — not architecture.
- If they ask a technical question, answer simply: \"I'll use modern web tools that are fast and reliable\" is fine.
- You're their technical co-founder. They describe the vision, you handle the engineering."
else
  SYSTEM_PROMPT="You are helping set up a brand new project in: ${PROJECT_DIR} (${PROJECT_NAME}).

YOUR APPROACH — be conversational, not robotic:
1. The user will tell you what they want to build. It might be vague — that's fine.
2. Ask smart follow-up questions to fill in the gaps (audience, features, deployment, budget). Keep it casual — one or two questions at a time, not a wall of interrogation.
3. Once you have enough context, propose a tech stack and architecture. Present it clearly and ask if they're happy with it.
4. When they approve, invoke the appropriate domain architect agent to validate the approach.
5. Generate a CLAUDE.md and present it. Only write it to disk when they explicitly approve.

IMPORTANT:
- This is a CONVERSATION. Be friendly. Ask questions. Don't dump everything at once.
- Do NOT assume deployment targets, auth providers, or paid services — ask first.
- If the user has no tech preference, recommend based on requirements and keep it simple."
fi

# Common CLAUDE.md requirements (appended to both modes)
SYSTEM_PROMPT="${SYSTEM_PROMPT}

THE CLAUDE.md MUST INCLUDE:
- Overview (what it is, who it's for)
- Tech stack table (Layer | Technology | Version — use SPECIFIC versions, not \"latest\")
- Project structure (directory layout)
- Development commands (install, dev, test, build — REAL commands for the chosen stack)
- Key patterns (auth approach, API design, component patterns, error handling)
- Git workflow and deployment approach
- Common pitfalls for the chosen stack

QUALITY RULES:
- Target under 200 lines — concise but comprehensive
- Every section should be actionable — if Claude reads it, it knows exactly what to do
- Document patterns as instructions to FOLLOW, not just know about
- This file is the project's constitution — it must be right before any code is written

AFTER THE CLAUDE.md IS SAVED:
- Re-read the CLAUDE.md you just wrote and treat it as your project rules from now on.
- Read ~/.claude/CLAUDE.md and ~/.claude/rules/ for the forge workflow rules.
- Ask the user what they'd like to do next. Follow the workflow rules from there."

claude --append-system-prompt "$SYSTEM_PROMPT"
