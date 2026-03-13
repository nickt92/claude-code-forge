# Claude Code Blueprint

A production-tested setup for Claude Code that transforms it from a helpful assistant into an engineering-governed development environment — adapted to who you are. Whether you're a CTO, a product manager, or someone building their first app with AI, the blueprint gives you the same quality standards with communication tuned to your role.

## What This Is

An opinionated, battle-tested configuration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI) that includes:

- **Persona system** — 12 roles from Vibe Coder to CTO, each assembling a tailored CLAUDE.md from reusable sections
- **5 rules files** — quality engineering, agent orchestration, commits, PRs, context management
- **3 enforcement hooks** — prompt classification, architect gate, transcript backup
- **Premium status line** — git state, model, context usage, cost, lines changed
- **18 specialist agent plugins** — architecture, security, testing, frontend, DevOps, and more
- **Install script** with onboarding wizard and health check verification

## Why This Exists

Claude Code reads instructions but doesn't always follow them. Through empirical testing, we discovered:

1. **Long CLAUDE.md files lose adherence.** Anthropic recommends under 200 lines — content buried at line 200+ gets ignored. Our setup splits into a focused main file + reference rules.

2. **Passive language gets treated as optional.** "Consider accessibility" is a suggestion. "Apply to ALL frontend work" is a command. Every line uses imperative voice with `NEVER`/`MUST`/`ALWAYS` emphasis.

3. **Knowing the rules ≠ following them.** Claude can articulate the workflow perfectly in retrospect but still skip it in practice. Hooks create forcing functions that block non-compliant behavior at write time.

4. **The tool must be named explicitly.** "Enter plan mode" is vague. "`Use the EnterPlanMode tool FIRST`" is unambiguous.

5. **One size doesn't fit all.** A product manager doesn't need to see tier classifications and agent names. A senior engineer does. Same quality standards, different communication.

## Persona System

The blueprint uses an **axis-based persona system** where each role selects values from 4 behavioral axes:

| Axis | Values | What It Controls |
|------|--------|-----------------|
| **Communication** | `plain` · `technical` · `expert` | Jargon level, explanation depth, analogies |
| **Autonomy** | `guided` · `moderate` · `high` | How often Claude asks vs proceeds |
| **Workflow** | `simplified` · `standard` · `advanced` | Internal ceremony visibility |
| **Depth** | `conceptual` · `practical` · `engineering` | Code-level detail in explanations |

### 12 Launch Personas

| # | Persona | Communication | Autonomy | Workflow | Depth |
|---|---------|--------------|----------|----------|-------|
| 1 | Product Manager | plain | guided | simplified | conceptual |
| 2 | Executive / Business Lead | plain | guided | simplified | conceptual |
| 3 | Designer (UI/UX) | plain | guided | simplified | practical |
| 4 | Data Analyst | technical | moderate | standard | practical |
| 5 | Data Scientist | technical | moderate | standard | engineering |
| 6 | Data Engineer | technical | moderate | advanced | engineering |
| 7 | Junior Developer | technical | moderate | standard | engineering |
| 8 | Senior Engineer | expert | high | advanced | engineering |
| 9 | CTO / Technical Architect | expert | high | advanced | engineering |
| 10 | DevOps / Platform Engineer | expert | high | advanced | engineering |
| 11 | Vibe Coder | plain | guided | simplified | conceptual |
| 12 | Hobbyist / Side Projects | plain | moderate | simplified | practical |

### How It Works

Each persona is a small JSON file that selects one value per axis. The installer reads it and concatenates the matching section files into a single CLAUDE.md under 200 lines.

**Adding a new persona** = create one JSON file. If existing axis values cover the behavior, zero section changes needed.

```json
{
  "schema_version": 1,
  "persona": "vibe-coder",
  "label": "Vibe Coder",
  "description": "I don't code but I want to build things with AI",
  "axes": {
    "communication": "plain",
    "autonomy": "guided",
    "workflow": "simplified",
    "depth": "conceptual"
  },
  "quality": ["core"]
}
```

### The Key Insight: Interpretation Directive

For non-technical personas, the workflow section includes an **interpretation directive** — Claude follows the same engineering rules internally but adapts how it communicates. A vibe coder sees "Here's my proposed approach" instead of "This is a significant-tier task requiring Phase 1 design gate." Quality is identical; jargon is not.

## The 4-Phase Workflow

Every task follows a structured workflow, with the rigor proportional to complexity:

```
Phase 1 — Design     (significant tasks only)
Phase 2 — Implement  (all tasks)
Phase 3 — Review     (all tasks, scope varies by tier)
Phase 4 — React      (on-demand: errors, incidents, debugging)
```

### 3-Tier Task Classification

| Tier | Criteria | What Happens |
|------|----------|-------------|
| **Trivial** | Single-file, clear requirements | Implement directly, code review before commit |
| **Moderate** | Multi-file, well-understood domain | Implement, domain architect + code review |
| **Significant** | New service, auth, architecture, ambiguous | Plan mode, architect review, approval, then implement |

### Enforcement Hooks

| Hook | Trigger | What It Does |
|------|---------|-------------|
| `prompt-classifier.sh` | First prompt | Detects significant task keywords, nudges classification |
| `architect-gate.sh` | Write/Edit tools | Blocks plan files without `## Architect Review` section |
| `backup-transcript.sh` | Before compaction | Saves full transcript to `~/.claude/backups/` |

## What's Included

```
claude-code-blueprint/
├── install.sh                          # Installer with onboarding wizard
├── statusline-command.sh               # Premium status line
├── lib/
│   └── platform.sh                     # Cross-platform utilities (macOS, Linux, WSL)
├── templates/
│   ├── profiles/                       # One JSON per persona (12 at launch)
│   │   ├── product-manager.json
│   │   ├── senior-engineer.json
│   │   ├── vibe-coder.json
│   │   └── ... (12 total)
│   ├── sections/                       # Axis-value section files (12 total)
│   │   ├── base.md                     # Always included — role, quality, rules
│   │   ├── communication-{plain,technical,expert}.md
│   │   ├── autonomy-{guided,moderate,high}.md
│   │   ├── workflow-{simplified,standard,advanced}.md
│   │   ├── quality-core.md             # Critical rules — all personas
│   │   └── quality-engineering.md      # Testing, a11y, perf — engineering depth
│   ├── settings.json                   # Hooks + status line + plugins config
│   └── rules/
│       ├── quality-engineering.md      # Testing, accessibility, performance
│       ├── agent-orchestration.md      # 4-phase model, 30+ specialist agents
│       ├── commit-and-delivery.md      # Conventional commits, dependency policy
│       ├── context-and-memory.md       # Compaction, session resumption
│       └── pull-requests.md            # PR format, layer grouping, test plans
├── hooks/
│   ├── prompt-classifier.sh            # Session-start task classification nudge
│   ├── architect-gate.sh               # Plan file validation
│   └── backup-transcript.sh            # Pre-compaction transcript backup
├── scripts/
│   ├── generate-project-claude.sh      # Brownfield: analyze existing codebase
│   └── init-project-claude.sh          # Greenfield: design architecture from scratch
└── examples/
    ├── project-CLAUDE.md               # Template for project-level overrides
    └── personas/
        ├── vibe-coder-CLAUDE.md        # Example assembled output (plain/guided)
        └── senior-engineer-CLAUDE.md   # Example assembled output (expert/advanced)
```

## Quick Start

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- macOS or Linux (WSL should work but is not fully tested)

### Install

```bash
git clone https://github.com/nickthorpe71/claude-code-blueprint.git
cd claude-code-blueprint
chmod +x install.sh
./install.sh
```

The installer will:
1. Ask you to pick a persona from the 12 available roles
2. Assemble a tailored CLAUDE.md from section files (verified under 200 lines)
3. Back up your existing configuration
4. Copy rules files, hooks, and status line
5. Merge settings (preserves your existing config)
6. Install 18 specialist plugins
7. Run health checks and assembly smoke tests

### Scripted Install (CI/automation)

```bash
./install.sh --profile senior-engineer
```

### Change Your Persona

```bash
./install.sh --reconfigure
```

### Verify

```bash
claude   # Start a new session
/memory  # Check files are loaded
```

### Uninstall

```bash
./install.sh --uninstall
```

## Project Onboarding (Brownfield)

For existing projects, the blueprint includes a generator that analyzes your codebase and produces a proper project-level CLAUDE.md — not a template with blanks, but a real analysis of your architecture, tech stack, patterns, and pitfalls.

```bash
cd /path/to/your-existing-project
~/.claude/scripts/generate-project-claude.sh
```

The script gathers context automatically (directory structure, dependencies, configs, git history), launches Claude Code with all that context, and lets you review and iterate interactively until the CLAUDE.md is right.

### Greenfield Projects

For new projects with no code yet:

```bash
mkdir my-new-project && cd my-new-project && git init
~/.claude/scripts/init-project-claude.sh
```

Interactive setup that helps you make architectural decisions and generates the CLAUDE.md before the first line of code.

For a simpler starting point, `examples/project-CLAUDE.md` provides a blank template you can fill in manually.

## Customization

### Adding a Persona

Create a JSON file in `templates/profiles/` with axis values and add the key to the `PERSONA_KEYS` array in `install.sh`. If existing axis values cover the behavior, no section changes needed.

### Adjusting Quality Standards

Edit `templates/rules/quality-engineering.md`:
- Change coverage targets (default: 85%)
- Add or remove accessibility requirements
- Adjust performance checklists

### Project-Level Overrides

Copy `examples/project-CLAUDE.md` to your project root as `CLAUDE.md`. Project-level instructions override global for project-specific concerns.

## Status Line

```
🌿 feat/thing ✦3 ↑2 │ 🧠 Opus │ ▐████░░░░▌ 42% │ 💰 38¢ │ ✏️ +156 −23 │ ⏱️ 12m
```

| Segment | What It Shows |
|---------|-------------|
| 🌿/🔗 | Git branch, dirty count, ahead/behind, stashes |
| 🧠 | Model (color-coded: Opus=red, Sonnet=cyan, Haiku=green) |
| ▐████░░▌ | Context window usage (green <70%, yellow 70-90%, red >90%) |
| 💰 | Session cost |
| ✏️ | Lines added/removed |
| ⏱️ | Session duration |

## Design Decisions

### Why hooks instead of just instructions?

Instructions tell Claude what to do. Hooks enforce it. The architect-gate hook literally blocks plan file writes that don't include an `## Architect Review` section.

### Why under 200 lines per CLAUDE.md?

Anthropic recommends it. Our testing showed content at line 200+ was frequently ignored. The persona system guarantees every assembled CLAUDE.md stays under the limit (verified at install time).

### Why axis-based personas instead of separate templates?

11 section files serve any number of personas. Adding a persona is one JSON file, not duplicating and maintaining a full CLAUDE.md template. The combinatorial approach scales without content drift.

## Maintenance

### Backup directory

```bash
du -sh ~/.claude/backups/
find ~/.claude/backups/ -mtime +30 -delete  # Clean old files
```

### Plugin updates

```bash
claude plugins update
```

### Health check

```bash
./install.sh  # Idempotent — re-running updates files and re-verifies
```

## Credits

Built through iterative testing and refinement with Claude Code itself. The setup evolved through real engineering work — not theoretical best practices, but patterns that survived contact with actual codebases.

### Agent Plugins

**[claude-code-workflows](https://github.com/wshobson/claude-code-workflows)** by [Will Hobson](https://github.com/wshobson) — 16 plugins providing 30+ specialist agents that make the 4-phase workflow possible. Without this project, there would be no architect review gate, no domain-specific routing, no code reviewer quality gate.

**[claude-code-plugins](https://github.com/anthropics/claude-code-plugins)** by Anthropic — official plugins:
- `context7` — real-time library documentation lookup
- `frontend-design` — UI/UX design quality for frontend work

### Tools

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) by Anthropic

## License

MIT