<div align="center">

# Claude Code Forge

**Forge Claude Code into an engineering-governed development environment — adapted to who you are.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-%E2%89%A51.0-blueviolet?style=flat-square)](https://docs.anthropic.com/en/docs/claude-code)
[![Personas](https://img.shields.io/badge/Personas-12-orange?style=flat-square)](#-persona-system)
[![Plugins](https://img.shields.io/badge/Plugins-18-green?style=flat-square)](#credits)

Whether you're a CTO, a product manager, or someone building their first app with AI — the forge gives you the same quality standards with communication tuned to your role.

</div>

---

<div align="center">

**12 Personas** · **18 Specialist Agents** · **4 Enforcement Hooks** · **6 Rules Files** · **Premium Status Line**

</div>

## Why This Exists

Claude Code reads instructions but doesn't always follow them. Through empirical testing, we discovered:

> **Long files lose adherence.** Content buried at line 200+ gets ignored. The forge assembles focused CLAUDE.md files under 200 lines — every time.

> **Passive language is treated as optional.** "Consider accessibility" is a suggestion. "Apply to ALL frontend work" is a command.

> **Knowing the rules ≠ following them.** Hooks create forcing functions that block non-compliant behavior at write time.

> **One size doesn't fit all.** A product manager doesn't need tier classifications and agent names. A senior engineer does. Same quality, different communication.

## ⚡ Quick Start

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- macOS or Linux (WSL should work but is not fully tested)

### Install

```bash
git clone https://github.com/nickt92/claude-code-forge.git
cd claude-code-forge
chmod +x install.sh
./install.sh
```

The installer walks you through a one-step persona selection, then:

1. Assembles a tailored CLAUDE.md from section files (verified under 200 lines)
2. Backs up your existing `~/.claude/` configuration
3. Copies rules files, hooks, and status line
4. Merges settings (preserves your existing config)
5. Installs 18 specialist plugins
6. Runs health checks and assembly smoke tests

### Scripted Install

```bash
./install.sh --profile senior-engineer    # Skip the wizard
./install.sh --reconfigure                # Change your persona later
./install.sh --uninstall                  # Restore backups
```

### Verify

```bash
claude     # Start a new session
/memory    # Check files are loaded
```

## 🔥 Persona System

The forge uses an **axis-based persona system**. Each role selects values from 4 behavioral axes — the installer reads the selection and assembles a tailored CLAUDE.md from reusable section files.

### The 4 Axes

| Axis | Values | What It Controls |
|:-----|:-------|:----------------|
| **Communication** | `plain` · `technical` · `expert` | Jargon level, explanation depth, analogies |
| **Autonomy** | `guided` · `moderate` · `high` | How often Claude asks vs proceeds |
| **Workflow** | `simplified` · `standard` · `advanced` | Internal ceremony visibility |
| **Depth** | `conceptual` · `practical` · `engineering` | Code-level detail in explanations |

### 12 Launch Personas

| # | Persona | Comm | Auto | Workflow | Depth | Quality |
|:-:|:--------|:----:|:----:|:--------:|:-----:|:-------:|
| 1 | **Product Manager** | plain | guided | simplified | conceptual | core |
| 2 | **Executive / Business Lead** | plain | guided | simplified | conceptual | core |
| 3 | **Designer (UI/UX)** | plain | guided | simplified | practical | core |
| 4 | **Data Analyst** | technical | moderate | standard | practical | core |
| 5 | **Data Scientist** | technical | moderate | standard | engineering | core + eng |
| 6 | **Data Engineer** | technical | moderate | advanced | engineering | core + eng |
| 7 | **Junior Developer** | technical | moderate | standard | engineering | core + eng |
| 8 | **Senior Engineer** | expert | high | advanced | engineering | core + eng |
| 9 | **CTO / Architect** | expert | high | advanced | engineering | core + eng |
| 10 | **DevOps / Platform** | expert | high | advanced | engineering | core + eng |
| 11 | **Vibe Coder** | plain | guided | simplified | conceptual | core |
| 12 | **Hobbyist** | plain | moderate | simplified | practical | core |

> **Note:** Some personas share identical axis configurations (e.g., Senior Engineer / CTO / DevOps all produce the same assembled CLAUDE.md). The distinct labels exist for wizard UX — pick the one that best describes you. The real behavioral differences come from the axis values, not the persona name.

### Adding a Persona

Create one JSON file. If existing axis values cover the behavior, zero section changes needed.

<details>
<summary><strong>Example: vibe-coder.json</strong></summary>

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

</details>

### The Key Insight: Interpretation Directive

For non-technical personas, the workflow section includes an **interpretation directive** — Claude follows the same engineering rules internally but adapts how it communicates:

| What happens internally | What the vibe coder sees |
|:------------------------|:-------------------------|
| "Significant-tier task, Phase 1 design gate" | "Here's my proposed approach" |
| "Invoking security-auditor agent" | "I'm reviewing this for security" |
| "Architect review approved with changes" | "I've refined the approach — here's what changed" |

Quality is identical. Jargon is not.

## 🔄 The 4-Phase Workflow

Every task follows a structured workflow, with rigor proportional to complexity:

```
Phase 1 — Design     (significant tasks only)
Phase 2 — Implement  (all tasks)
Phase 3 — Review     (all tasks, scope varies by tier)
Phase 4 — React      (on-demand: errors, incidents, debugging)
```

### 3-Tier Task Classification

| Tier | Criteria | What Happens |
|:-----|:---------|:-------------|
| **Trivial** | Single-file, clear requirements | Implement directly, code review before commit |
| **Moderate** | Multi-file, well-understood domain | Implement, domain architect + code review |
| **Significant** | New service, auth, architecture | Plan mode → architect review → approval → implement |

### 🛡 Enforcement Hooks

| Hook | Trigger | What It Does |
|:-----|:--------|:-------------|
| `session-init.sh` | First prompt per session | Persona-aware classification nudge (adapts to autonomy level) |
| `architect-gate.sh` | Write/Edit tools | Blocks plan files without `## Architect Review` section |
| `commit-validator.sh` | Bash tool (git commit) | Blocks AI attribution, warns on non-conventional format |
| `backup-transcript.sh` | Before compaction | Saves full transcript to `~/.claude/backups/` |

## 📦 What's Included

```
claude-code-forge/
├── install.sh                          # Installer with onboarding wizard
├── statusline-command.sh               # Premium status line
├── lib/
│   └── platform.sh                     # Cross-platform (macOS, Linux, WSL)
├── templates/
│   ├── profiles/                       # 12 persona JSON configs
│   ├── sections/                       # 15 axis-value section files
│   ├── settings.json                   # Hooks + status line + plugins
│   └── rules/                          # 5 rules files
├── hooks/                              # 4 enforcement hooks
├── scripts/
│   ├── generate-project-claude.sh      # Brownfield project onboarding
│   └── init-project-claude.sh          # Greenfield project setup
└── examples/
    ├── project-CLAUDE.md               # Project-level override template
    ├── personas/                       # Assembled output examples
    └── document-chain/                 # PROJECT/REQUIREMENTS/ROADMAP examples
```

## 🏗 Project Onboarding

### Brownfield (Existing Projects)

The forge includes a generator that analyzes your codebase and produces a project-level CLAUDE.md — not a template with blanks, but a real analysis of your architecture, tech stack, patterns, and pitfalls.

```bash
cd /path/to/your-existing-project
~/.claude/scripts/generate-project-claude.sh
```

### Greenfield (New Projects)

Interactive setup that helps you make architectural decisions and generates the CLAUDE.md before the first line of code.

```bash
mkdir my-new-project && cd my-new-project && git init
~/.claude/scripts/init-project-claude.sh
```

For a simpler starting point, `examples/project-CLAUDE.md` provides a template you can fill in manually.

### Document Chain (Optional)

For multi-session or multi-phase projects, the forge supports a **document chain** — structured files that give Claude persistent context about your project's vision, requirements, and progress:

```
your-project/
├── CLAUDE.md         # Project-level Claude instructions (always)
├── PROJECT.md        # Vision, goals, constraints, stakeholders
├── REQUIREMENTS.md   # Scoped requirements with acceptance criteria
└── ROADMAP.md        # Phased plan with progress tracking
```

These are team artifacts committed to git. Claude checks for them at session start (via `rules/project-setup.md`) and offers to help generate them when you describe new work. Templates are in `templates/document-chain/`, and filled-in examples are in `examples/document-chain/`.

## 📊 Status Line

```
🌿 feat/thing ✦3 ↑2 │ 🧠 Opus │ ▐████░░░░▌ 42% │ 💰 38¢ │ ✏️ +156 −23 │ ⏱️ 12m
```

| Segment | What It Shows |
|:--------|:-------------|
| 🌿/🔗 | Git branch, dirty count, ahead/behind, stashes |
| 🧠 | Model (color-coded: Opus=red, Sonnet=cyan, Haiku=green) |
| ▐████░░▌ | Context window usage (green <70%, yellow 70-90%, red >90%) |
| 💰 | Session cost |
| ✏️ | Lines added/removed |
| ⏱️ | Session duration |

## 🎛 Customization

<details>
<summary><strong>Adjusting Quality Standards</strong></summary>

Edit `templates/rules/quality-engineering.md`:
- Change coverage targets (default: 85%)
- Add or remove accessibility requirements
- Adjust performance checklists

</details>

<details>
<summary><strong>Project-Level Overrides</strong></summary>

Copy `examples/project-CLAUDE.md` to your project root as `CLAUDE.md`. Project-level instructions override global for project-specific concerns (tech stack, patterns, conventions).

</details>

<details>
<summary><strong>Adding Custom Agents</strong></summary>

The plugin system supports any specialist. Add agents to `templates/rules/agent-orchestration.md` in the appropriate phase and update the domain architect routing table.

</details>

## 🧠 Design Decisions

<details>
<summary><strong>Why hooks instead of just instructions?</strong></summary>

Instructions tell Claude what to do. Hooks enforce it. The architect-gate hook literally blocks plan file writes that don't include an `## Architect Review` section. Claude can't skip the step even if it wants to.

</details>

<details>
<summary><strong>Why under 200 lines per CLAUDE.md?</strong></summary>

Anthropic recommends it. Our testing showed content at line 200+ was frequently ignored. The persona system guarantees every assembled CLAUDE.md stays under the limit (verified at install time).

</details>

<details>
<summary><strong>Why axis-based personas instead of separate templates?</strong></summary>

15 section files serve any number of personas. Adding a persona is one JSON file, not duplicating and maintaining a full CLAUDE.md template. The combinatorial approach scales without content drift.

</details>

## 🔧 Maintenance

```bash
du -sh ~/.claude/backups/                       # Check backup size
find ~/.claude/backups/ -mtime +30 -delete      # Clean old transcripts
claude plugins update                           # Update plugins
./install.sh                                    # Re-run (idempotent)
```

## Credits

Built through iterative testing and refinement with Claude Code itself — patterns that survived contact with actual codebases, not theoretical best practices.

### Agent Plugins

**[claude-code-workflows](https://github.com/wshobson/claude-code-workflows)** by [Will Hobson](https://github.com/wshobson) — 16 plugins providing 30+ specialist agents that make the 4-phase workflow possible. Without this project, there would be no architect review gate, no domain-specific routing, no code reviewer quality gate.

**[claude-code-plugins](https://github.com/anthropics/claude-code-plugins)** by Anthropic — official plugins:
- `context7` — real-time library documentation lookup
- `frontend-design` — UI/UX design quality for frontend work

### Tools

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) by Anthropic

## License

MIT