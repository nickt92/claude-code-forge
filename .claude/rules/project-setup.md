# Project Setup & Document Chain

## Session Start — Project Context Check

At the start of every session, check for these files in the project root:

| File | Purpose | Required? |
|------|---------|-----------|
| `CLAUDE.md` | Project-level Claude instructions | Yes — every project needs one |
| `PROJECT.md` | Vision, goals, constraints, stakeholders | Recommended for multi-session work |
| `REQUIREMENTS.md` | Scoped requirements with phases | Recommended for feature work |
| `ROADMAP.md` | Phased plan with progress tracking | Recommended for multi-phase projects |

**If CLAUDE.md is missing:** Offer to generate one. For existing codebases, run `~/.claude/scripts/generate-project-claude.sh`. For new projects, run `~/.claude/scripts/init-project-claude.sh`.

**If PROJECT.md/REQUIREMENTS.md/ROADMAP.md are missing** and the user describes non-trivial new work: suggest creating them. Do NOT create automatically — propose and wait for approval.

**If ROADMAP.md exists:** Check progress status before starting new work. Identify which phase is active and what was completed.

## Document Chain Rules

These files are **team artifacts** committed to git — not tooling config.

### PROJECT.md
- Defines the product: what it is, who it's for, why it exists
- Includes constraints (budget, timeline, compliance, team size)
- Updated rarely — only when vision or constraints change
- Claude reads this to understand the "why" behind decisions

### REQUIREMENTS.md
- Scoped to current work (a feature, a milestone, a sprint)
- Organized by priority (must-have, should-have, nice-to-have)
- Each requirement has acceptance criteria
- Updated as requirements are refined or completed

### ROADMAP.md
- Phased delivery plan with concrete milestones
- Each phase has status: planned / in-progress / complete
- Dependencies between phases are explicit
- Updated after each significant milestone

### Generation Flow
1. User describes what they want to build
2. Claude asks clarifying questions (stakeholders, constraints, timeline)
3. Claude drafts the document and presents for review
4. User approves, modifies, or rejects
5. Only then does Claude write the file
6. Files are committed to git alongside code

### Update Flow
- After completing a phase or milestone, propose ROADMAP.md updates
- After requirements change, propose REQUIREMENTS.md updates
- Always show the diff before writing — NEVER update silently