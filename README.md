# Claude Code Blueprint

A production-tested setup for Claude Code that transforms it from a helpful assistant into an engineering-governed development environment. Hooks enforce workflow compliance, specialist agents provide domain expertise, and structured rules ensure consistency across sessions.

## What This Is

An opinionated, battle-tested configuration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI) that includes:

- **Global CLAUDE.md** (136 lines) — behavioral directives that Claude follows every session
- **5 rules files** — quality engineering, agent orchestration, commits, PRs, context management
- **3 enforcement hooks** — prompt classification, architect gate, transcript backup
- **Premium status line** — git state, model, context usage, cost, lines changed
- **18 specialist agent plugins** — architecture, security, testing, frontend, DevOps, and more
- **Install script** with health check verification

## Why This Exists

Claude Code reads instructions but doesn't always follow them. Through empirical testing, we discovered:

1. **Long CLAUDE.md files lose adherence.** Anthropic recommends under 200 lines — content buried at line 200+ gets ignored. Our setup splits into a focused main file + reference rules.

2. **Passive language gets treated as optional.** "Consider accessibility" is a suggestion. "Apply to ALL frontend work" is a command. Every line uses imperative voice with `NEVER`/`MUST`/`ALWAYS` emphasis.

3. **Knowing the rules ≠ following them.** Claude can articulate the workflow perfectly in retrospect but still skip it in practice. Hooks create forcing functions that block non-compliant behavior at write time.

4. **The tool must be named explicitly.** "Enter plan mode" is vague. "`Use the EnterPlanMode tool FIRST`" is unambiguous. "Invoke the architect" is unclear. "`Run the architect via the Agent tool with subagent_type set to backend-development:backend-architect`" works.

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
├── README.md                           # You are here
├── install.sh                          # One-command installer with health check
├── statusline-command.sh               # Premium status line (277 lines)
├── templates/
│   ├── CLAUDE.md                       # Global behavioral directives (137 lines)
│   ├── settings.json                   # Hooks + status line + plugins config
│   └── rules/
│       ├── quality-engineering.md      # Testing, accessibility, performance, observability
│       ├── agent-orchestration.md      # 4-phase model, 30+ specialist agent routing
│       ├── commit-and-delivery.md      # Conventional commits, dependency policy
│       ├── context-and-memory.md       # Compaction, session resumption, context efficiency
│       └── pull-requests.md            # PR format, layer grouping, test plans
├── hooks/
│   ├── prompt-classifier.sh            # Session-start task classification nudge
│   ├── architect-gate.sh               # Plan file validation + classification nudge
│   └── backup-transcript.sh            # Pre-compaction transcript backup (30-day auto-cleanup)
├── scripts/
│   ├── generate-project-claude.sh      # Brownfield: analyze existing codebase
│   └── init-project-claude.sh          # Greenfield: design architecture from scratch
└── examples/
    └── project-CLAUDE.md               # Template for project-level overrides
```

## Quick Start

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)

### Install

```bash
git clone https://github.com/nickthorpe71/claude-code-blueprint.git
cd claude-code-blueprint
chmod +x install.sh
./install.sh
```

The installer will:
1. Back up your existing `~/.claude/CLAUDE.md` and `settings.json`
2. Copy all template files, hooks, and status line
3. Merge settings (preserves your existing config)
4. Install 18 specialist plugins
5. Run a health check to verify everything

### Verify

```bash
# Start a new session
claude

# Check files are loaded
/memory
```

### Uninstall

```bash
./install.sh --uninstall
```

Restores your backed-up configuration.

## Project Onboarding (Brownfield)

For existing projects, the blueprint includes a generator that analyzes your codebase and produces a proper project-level CLAUDE.md — not a template with blanks, but a real analysis of your architecture, tech stack, patterns, and pitfalls.

```bash
cd /path/to/your-existing-project
~/.claude/scripts/generate-project-claude.sh
```

The script:
1. **Gathers context automatically** — directory structure, dependency files (package.json, requirements.txt, go.mod, etc.), config files (tsconfig, docker-compose, CI/CD), git history, test structure, existing docs
2. **Launches Claude Code** with all that context and a comprehensive prompt
3. **Claude analyzes the codebase** — architecture, tech stack with specific versions, development commands, patterns, testing conventions, deployment, common pitfalls
4. **You review and iterate** interactively until the CLAUDE.md is right
5. **Claude writes the file** only when you explicitly approve

The generated CLAUDE.md targets under 200 lines and uses the same structure that proved effective in production projects — specific versions, real commands, actual patterns, not generic placeholders.

### Greenfield Projects

For new projects with no code yet, the blueprint includes an interactive setup that helps you make architectural decisions and generates the CLAUDE.md before the first line of code:

```bash
mkdir my-new-project && cd my-new-project && git init
~/.claude/scripts/init-project-claude.sh
```

The script:
1. **Asks about your project** — what you're building, who it's for, constraints
2. **Asks about tech preferences** — or recommends a stack based on requirements
3. **Claude proposes architecture** — tech stack with specific versions, directory structure, patterns, workflow
4. **You approve or adjust** — iterative conversation until the design is right
5. **Architect agent validates** — reviews the proposed architecture for scaling, security, and pattern concerns
6. **Generates the project CLAUDE.md** — written only when you approve

The CLAUDE.md becomes the project's constitution — every future Claude Code session follows it. As the project evolves, update it to reflect new patterns, conventions, and decisions that emerge.

For a simpler starting point, `examples/project-CLAUDE.md` provides a blank template you can fill in manually.

## Customization

### Adding Custom Agents

The plugin system supports any specialist. To add a Salesforce agent, for example:

1. Create a plugin or use an existing one that provides Salesforce expertise
2. Add the agent to `templates/rules/agent-orchestration.md` in the appropriate phase
3. Update the domain architect routing table in Phase 1

### Adjusting Quality Standards

Edit `templates/rules/quality-engineering.md`:
- Change coverage targets (default: 85%)
- Add or remove accessibility requirements
- Adjust performance checklists
- Modify observability requirements

### Project-Level Overrides

Copy `examples/project-CLAUDE.md` to your project root as `CLAUDE.md`. Project-level instructions override global for project-specific concerns (tech stack, patterns, conventions).

## Status Line

The status line shows real-time session information:

```
🌿 feat/thing ✦3 ↑2 │ 🧠 Opus │ ▐████░░░░▌ 42% │ 💰 38¢ │ ✏️ +156 −23 │ ⏱️ 12m
```

| Segment | What It Shows |
|---------|-------------|
| 🌿/🔗 | Git branch (🔗 = worktree), dirty count, ahead/behind, stashes |
| 🧠 | Model (color-coded: Opus=red, Sonnet=cyan, Haiku=green) |
| 🤖 | Agent name (when using `--agent`) |
| ▐████░░▌ | Context window usage (green <70%, yellow 70-90%, red >90%) |
| 💰 | Session cost (dim <$1, yellow $1-5, red >$5) |
| ✏️ | Lines added/removed |
| ⏱️ | Session duration |
| INS/VIS/NOR | Vim mode (when vim mode is enabled) |

Branch colors: red = main/master/detached, yellow = develop, blue = feature branches.

## Design Decisions

### Why hooks instead of just instructions?

Instructions tell Claude what to do. Hooks enforce it. The architect-gate hook literally blocks plan file writes that don't include an `## Architect Review` section. Claude can't skip the step even if it wants to.

### Why 136 lines in the main CLAUDE.md?

Anthropic recommends under 200 lines. Our testing showed that content at line 200+ was frequently ignored. The main file contains only behavioral commands (what to do, what never to do). Reference material (lookup tables, checklists) lives in rules files that load with equal priority but don't dilute the main file's attention.

### Why imperative language?

Empirical testing showed "Consider accessibility" gets treated as optional, while "Apply to ALL frontend work" gets followed. Every line uses action verbs and emphasis markers (`NEVER`, `MUST`, `ALWAYS`, `IMPORTANT`).

### Why name tools explicitly?

Claude understood "enter plan mode" as a concept but didn't use the `EnterPlanMode` tool. Once we wrote "Use the `EnterPlanMode` tool FIRST", compliance jumped to near-100%. Same for "invoke via the Agent tool with `subagent_type`".

## Maintenance

### Backup directory

The transcript backup hook saves files to `~/.claude/backups/`. Check size periodically:

```bash
du -sh ~/.claude/backups/
# Clean files older than 30 days:
find ~/.claude/backups/ -mtime +30 -delete
```

### Plugin updates

```bash
claude plugins update
```

### Health check

Re-run the installer's health check anytime:

```bash
./install.sh  # It's idempotent — re-running just updates files
```

## Credits

Built through iterative testing and refinement with Claude Code itself. The setup evolved through real engineering work — not theoretical best practices, but patterns that survived contact with actual codebases.

### Agent Plugins

The entire specialist agent orchestration model depends on two plugin ecosystems:

**[claude-code-workflows](https://github.com/wshobson/claude-code-workflows)** by [Will Hobson](https://github.com/wshobson) — the foundation. 16 plugins providing 30+ specialist agents that make the 4-phase workflow possible:

| Plugin | Agents Provided |
|--------|----------------|
| `backend-development` | backend-architect, graphql-architect, event-sourcing-architect |
| `comprehensive-review` | architect-review, code-reviewer, security-auditor |
| `database-design` | database-architect, sql-pro |
| `frontend-mobile-development` | frontend-developer, mobile-developer |
| `full-stack-orchestration` | performance-engineer, test-automator, security-auditor, deployment-engineer |
| `javascript-typescript` | typescript-pro, javascript-pro |
| `cicd-automation` | cloud-architect, deployment-engineer, kubernetes-architect, terraform-specialist, devops-troubleshooter |
| `cloud-infrastructure` | network-engineer, hybrid-cloud-architect, service-mesh-expert |
| `debugging-toolkit` | debugger, dx-optimizer |
| `error-debugging` | error-detective |
| `tdd-workflows` | tdd-orchestrator, code-reviewer |
| `code-refactoring` | legacy-modernizer, code-reviewer |
| `dependency-management` | legacy-modernizer |
| `documentation-generation` | docs-architect, api-documenter, mermaid-expert, tutorial-engineer |
| `startup-business-analyst` | startup-analyst |
| `hr-legal-compliance` | legal-advisor, hr-pro |

Without this project, there would be no architect review gate, no domain-specific routing, no code reviewer quality gate — essentially no engineering governance. The blueprint is the orchestration layer; claude-code-workflows provides the specialists.

**[claude-code-plugins](https://github.com/anthropics/claude-code-plugins)** by Anthropic — official plugins:
- `context7` — real-time library documentation lookup (ensures Claude uses current APIs, not stale training knowledge)
- `frontend-design` — UI/UX design quality for frontend work

### Tools

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) by Anthropic — the CLI that makes all of this possible

## License

MIT