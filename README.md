<div align="center">

# Claude Code Forge

**Forge Claude Code into an engineering-governed development environment — adapted to who you are.**

[![Tests](https://github.com/nickt92/claude-code-forge/actions/workflows/test.yml/badge.svg)](https://github.com/nickt92/claude-code-forge/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-%E2%89%A51.0-blueviolet?style=flat-square)](https://docs.anthropic.com/en/docs/claude-code)
[![Personas](https://img.shields.io/badge/Personas-12-orange?style=flat-square)](#-persona-system)
[![Plugins](https://img.shields.io/badge/Plugins-18-green?style=flat-square)](#credits)

Whether you're a CTO, a product manager, or someone building their first app with AI — the forge gives you the same quality standards with communication tuned to your role.

</div>

---

<div align="center">

**12 Personas** · **18 Specialist Agents** · **4 Enforcement Hooks** · **7 Rules Files** · **173 Tests** · **Premium Status Line**

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
2. Backs up your existing `~/.claude/` configuration automatically
3. Copies rules files, hooks, scripts, and status line
4. Merges settings (hooks and plugins added additively — your existing config is preserved)
5. Installs 18 specialist plugins
6. Runs health checks and assembly smoke tests

### Scripted Install

```bash
./install.sh --profile senior-engineer    # Skip the wizard
./install.sh --reconfigure                # Change your persona later
./install.sh --check                      # Verify installation without re-installing
./install.sh --uninstall                  # Remove forge files, restore backups
./install.sh --quiet --profile vibe-coder # Minimal output (CI-friendly)
./install.sh --debug                      # Verbose trace of each step
./install.sh --help                       # Show all options
```

### Verify

```bash
claude      # Start a new session
/memory     # Check files are loaded
```

## 📦 What Gets Installed

The forge writes only to `~/.claude/`. Before touching anything, it snapshots your existing configuration to `~/.claude/forge-backup/`. The `--uninstall` flag reads that snapshot and restores exactly what was there before.

```
~/.claude/
├── CLAUDE.md                     # Assembled from your persona (replaces existing)
├── profile.json                  # Your persona config (for hooks to read)
├── statusline-command.sh         # Premium status line script
├── settings.json                 # Forge hooks + plugins merged into existing config
├── rules/
│   ├── agent-orchestration.md   # 4-phase workflow, specialist routing table
│   ├── commit-and-delivery.md   # Commit format, dependency policy
│   ├── context-and-memory.md    # Session resumption, compaction protection
│   ├── project-setup.md         # Document chain, project onboarding
│   ├── pull-requests.md         # PR format standards
│   ├── quality-engineering.md   # Testing pyramid, coverage targets, accessibility
│   └── scope-discipline.md      # Task classification guard rails
├── hooks/
│   ├── session-init.sh          # First-prompt nudge (persona-aware)
│   ├── architect-gate.sh        # Blocks plan files without architect review
│   ├── commit-validator.sh      # Blocks AI attribution, warns on bad format
│   └── backup-transcript.sh     # Saves transcript before context compaction
├── scripts/
│   ├── generate-project-claude.sh  # Brownfield onboarding
│   └── init-project-claude.sh      # Greenfield project setup
├── lib/
│   └── ui.sh                    # Shared output library (used by scripts)
└── forge-backup/
    ├── manifest.json             # What was backed up and what was installed
    ├── CLAUDE.md                 # Your original CLAUDE.md (if any)
    ├── settings.json             # Your original settings.json (if any)
    └── rules/, hooks/, ...       # Any pre-existing files in these directories
```

**Settings merge strategy:** Hooks and plugins are added additively — the forge never removes your existing hooks or plugins. The `statusLine` and `alwaysThinkingEnabled` keys are set by the template. All other keys you have in `settings.json` are preserved unchanged.

**Uninstall is clean.** The manifest records exactly which files were installed and which were pre-existing. `--uninstall` restores the pre-existing files, removes forge-only files, and surgically unmerges forge additions from `settings.json` — including any plugins or hooks you added after installation.

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

Create one JSON file. If existing axis values cover the behavior, zero section changes are needed.

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
| `session-init.sh` | First prompt per session | Persona-aware classification nudge (language adapts to autonomy level) |
| `architect-gate.sh` | Write/Edit tools | Blocks plan files without `## Architect Review` section |
| `commit-validator.sh` | Bash tool (git commit) | Blocks AI attribution, warns on non-conventional format |
| `backup-transcript.sh` | Before compaction | Saves full transcript to `~/.claude/backups/` |

## 🖥 CLI Reference

```
Usage:
  ./install.sh                         Interactive wizard
  ./install.sh --profile <name>        Non-interactive install
  ./install.sh --reconfigure           Re-run the persona wizard
  ./install.sh --uninstall             Remove forge files, restore backups
  ./install.sh --check                 Run health checks only (no install)
  ./install.sh --quiet --profile <n>   Minimal output (CI-friendly)
  ./install.sh --debug --profile <n>   Trace each verification step
  ./install.sh --help                  Show this help

Available profiles:
  product-manager, executive, designer, analyst,
  data-scientist, data-engineer, junior-dev, senior-engineer,
  cto-architect, devops-engineer, vibe-coder, hobbyist

Environment:
  NO_COLOR=1     Disable colored output
  UI_QUIET=true  Same as --quiet
  UI_DEBUG=true  Same as --debug
```

**`--check`** runs health checks against your existing `~/.claude/` installation without modifying anything. Useful after updating the repo to see if you need to re-run the installer.

**`--reconfigure`** always runs the wizard, even if a profile is already installed. Use this to switch personas.

**`--uninstall`** shows a preview of what will be removed and restored before prompting for confirmation. Optionally uninstalls the 18 forge plugins too.

**`--quiet`** suppresses all output except failures and warnings. Designed for scripted or CI environments where you want a clean log.

**`--debug`** prints each verification step to stderr. Useful when a health check fails and the high-level message isn't enough.

## 📊 Status Line

```
🌿 feat/thing ✦3 ↑2 │ 🧠 Opus │ ▐████░░░░▌ 42% │ 💰 38¢ │ ✏️ +156 −23 │ ⏱️ 12m
```

| Segment | What It Shows |
|:--------|:-------------|
| **Branch** 🌿/🔗 | Git branch, dirty count, ahead/behind, stashes |
| **Model** 🧠 | Active model (color-coded: Opus=red, Sonnet=cyan, Haiku=green) |
| **Context** | Context window usage bar (green <70%, yellow 70-90%, red >90%) |
| **Cost** 💰 | Session cost |
| **Changes** ✏️ | Lines added/removed |
| **Time** ⏱️ | Session duration |

## 🏗 Project Onboarding

### Brownfield (Existing Projects)

Analyzes your codebase and generates a project-level CLAUDE.md — not a template with blanks, but a real analysis of your architecture, tech stack, patterns, and pitfalls.

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

These are team artifacts committed to git. Claude checks for them at session start and offers to help generate them when you describe new work. Templates are in `templates/document-chain/` and filled-in examples are in `examples/document-chain/`.

## 🎛 Customization

<details>
<summary><strong>Adjusting Quality Standards</strong></summary>

Edit `templates/rules/quality-engineering.md`:
- Change coverage targets (default: 85%)
- Add or remove accessibility requirements
- Adjust performance checklists

Then re-run `./install.sh` to install the updated rules.

</details>

<details>
<summary><strong>Project-Level Overrides</strong></summary>

Copy `examples/project-CLAUDE.md` to your project root as `CLAUDE.md`. Project-level instructions override global for project-specific concerns (tech stack, patterns, conventions). The global `~/.claude/CLAUDE.md` still applies for everything not overridden.

</details>

<details>
<summary><strong>Adding Custom Agents</strong></summary>

The plugin system supports any specialist. Add agents to `templates/rules/agent-orchestration.md` in the appropriate phase and update the domain architect routing table. Re-run `./install.sh` to propagate changes.

</details>

<details>
<summary><strong>Switching Personas</strong></summary>

```bash
./install.sh --reconfigure
```

This re-runs the wizard, re-assembles `~/.claude/CLAUDE.md` from the new profile, and updates `~/.claude/profile.json`. Hooks read `profile.json` at runtime, so the new persona takes effect immediately on the next `claude` session — no restart required.

</details>

## ❓ Troubleshooting

<details>
<summary><strong>Health check fails after install</strong></summary>

Run `./install.sh --check` to see exactly which checks are failing. Common causes:

- **Missing hooks or rules files** — re-run `./install.sh` to reinstall
- **Hooks not executable** — the installer sets `chmod +x` on all hooks; if this fails, set manually: `chmod +x ~/.claude/hooks/*.sh`
- **Plugin count below 15** — the `claude plugins add` command occasionally fails silently on bad network. Re-run `./install.sh` to retry plugin installation

</details>

<details>
<summary><strong>Claude doesn't seem to be following the rules</strong></summary>

Run `/memory` at the start of a Claude session. If `~/.claude/CLAUDE.md` and the rules files are not listed, Claude isn't loading them.

Three things to verify:
1. `~/.claude/CLAUDE.md` exists and is under 200 lines (`wc -l ~/.claude/CLAUDE.md`)
2. `~/.claude/rules/` contains the 7 rules files
3. Claude Code version is 1.0 or newer (`claude --version`)

If the files are loaded but rules aren't followed, check that you're at the start of a fresh session. Long-running sessions accumulate context and can lose instruction adherence — start a new session with `/clear` or open a new terminal.

</details>

<details>
<summary><strong>The architect-gate hook is blocking my file</strong></summary>

The hook blocks writes to `~/.claude/plans/` that don't include an `## Architect Review` section. This is intentional — the gate enforces that you run the domain architect agent before finalizing a plan.

To pass the gate, add the section to your plan file:

```markdown
## Architect Review
- **Reviewer:** backend-development:backend-architect
- **Verdict:** approved
- **Key findings:** ...
- **Adjustments:** none
```

If you're writing a plan outside `~/.claude/plans/`, the hook doesn't apply.

</details>

<details>
<summary><strong>commit-validator is blocking my commit</strong></summary>

The validator blocks commits containing AI attribution (`Co-Authored-By: Claude`, `Generated with Claude Code`, etc.). Remove the attribution and commit again.

It also warns (but does not block) on non-conventional commit format. The expected format is:

```
feat(scope): description
fix(auth): description
chore(deps): description
```

If you see a warning but want to proceed anyway, the commit still goes through — the warning is informational.

</details>

<details>
<summary><strong>I already have hooks or plugins configured</strong></summary>

The settings merge is additive. The forge appends its hooks to your existing hook arrays and adds its plugins to your existing plugin object. Your hooks and plugins are never removed.

If you're concerned about conflicts, check `~/.claude/forge-backup/manifest.json` — the `installed.settings_additions` field shows exactly what the forge added to your `settings.json`.

</details>

<details>
<summary><strong>--uninstall didn't restore my original settings.json</strong></summary>

Uninstall reads `~/.claude/forge-backup/manifest.json` to determine what to restore. If the manifest is missing (e.g., it was deleted manually), uninstall falls back to best-effort removal using the known forge file list.

If you had a custom `settings.json` before installing, the original is in `~/.claude/forge-backup/settings.json`. You can restore it manually:

```bash
cp ~/.claude/forge-backup/settings.json ~/.claude/settings.json
```

</details>

<details>
<summary><strong>WSL or Linux: colors or spinner look broken</strong></summary>

The UI library auto-detects TTY and color support. If output looks garbled, disable colors:

```bash
NO_COLOR=1 ./install.sh --profile senior-engineer
```

On non-interactive environments (CI, pipes), the spinner and progress counter automatically fall back to plain text output.

</details>

## 🧪 Testing

173 automated tests using [bats-core](https://github.com/bats-core/bats-core), run on every push via GitHub Actions (macOS + Ubuntu).

```bash
./test/run_tests.sh              # Run all tests
./test/run_tests.sh unit         # Hook unit tests only
./test/run_tests.sh integration  # Assembly, merge, install flow
./test/run_tests.sh validation   # Profile schema, section coverage
```

> **Note:** bats-core is included as a git submodule. If the test runner fails to find it, run `git submodule update --init --recursive` first.

| Suite | Tests | What It Covers |
|:------|------:|:---------------|
| **Unit** | 84 | Commit validator, architect gate, session init, backup transcript, platform detection, UI library |
| **Integration** | 65 | Assembly pipeline, settings merge/unmerge, install flow, backup and restore |
| **Validation** | 24 | Profile schema integrity, section file coverage, settings template structure |

All tests run in a sandbox (`$HOME` redirected to a temp directory) — your real `~/.claude/` is never touched.

## 📁 Repository Structure

```
claude-code-forge/
├── install.sh                          # Installer with onboarding wizard
├── statusline-command.sh               # Premium status line
├── lib/
│   ├── ui.sh                           # Output library (colors, spinner, progress)
│   ├── platform.sh                     # Cross-platform detection (macOS, Linux, WSL)
│   ├── assembly.sh                     # CLAUDE.md assembly from profile + sections
│   ├── settings-merge.sh               # Additive settings merge
│   ├── settings-unmerge.sh             # Surgical settings restore for uninstall
│   ├── forge-inventory.sh              # Runtime discovery of shipped files
│   ├── manifest.sh                     # Backup manifest CRUD and validation
│   └── uninstall.sh                    # Uninstall orchestration
├── templates/
│   ├── profiles/                       # 12 persona JSON configs
│   ├── sections/                       # 15 axis-value section files
│   ├── settings.json                   # Hooks + status line + plugins template
│   ├── rules/                          # 7 rules files installed to ~/.claude/rules/
│   └── document-chain/                 # PROJECT/REQUIREMENTS/ROADMAP templates
├── hooks/                              # 4 enforcement hooks
├── scripts/
│   ├── generate-project-claude.sh      # Brownfield project onboarding
│   └── init-project-claude.sh          # Greenfield project setup
├── test/
│   ├── unit/                           # 84 tests: hooks and platform
│   ├── integration/                    # 65 tests: assembly, merge, install flow
│   ├── validation/                     # 24 tests: schema and coverage checks
│   ├── helpers/                        # Shared test helper
│   ├── libs/                           # bats-core, bats-support, bats-assert, bats-file
│   └── run_tests.sh                    # Test runner
└── examples/
    ├── project-CLAUDE.md               # Project-level override template
    ├── personas/                       # Assembled CLAUDE.md output examples
    └── document-chain/                 # Filled-in PROJECT/REQUIREMENTS/ROADMAP examples
```

## 🧠 Design Decisions

<details>
<summary><strong>Why hooks instead of just instructions?</strong></summary>

Instructions tell Claude what to do. Hooks enforce it. The `architect-gate` hook literally blocks plan file writes that don't include an `## Architect Review` section. Claude can't skip the step even if it wants to. The `commit-validator` hook blocks AI attribution at the moment of commit — not as a reminder to remember later.

</details>

<details>
<summary><strong>Why under 200 lines per CLAUDE.md?</strong></summary>

Anthropic recommends it. Our testing showed content at line 200+ was frequently ignored in long sessions. The persona system guarantees every assembled CLAUDE.md stays under the limit (the health check verifies all 12 profiles at install time).

</details>

<details>
<summary><strong>Why axis-based personas instead of separate templates?</strong></summary>

15 section files serve any number of personas. Adding a persona is one JSON file, not duplicating and maintaining a full CLAUDE.md template. The combinatorial approach scales without content drift — when you update a section file, every persona that uses it gets the update automatically on the next install.

</details>

<details>
<summary><strong>Why is the backup manifest-based instead of timestamped copies?</strong></summary>

Timestamped backups accumulate and require manual cleanup. The manifest approach takes a single snapshot on first install and freezes it — re-installs don't overwrite the original backup, so you always have a clean restore point regardless of how many times you update. The manifest also records what the forge added to `settings.json` so uninstall can be surgical rather than destructive.

</details>

## 🔧 Maintenance

```bash
./install.sh --check                            # Verify current installation
./install.sh                                    # Re-run to pick up forge updates (idempotent)
./install.sh --reconfigure                      # Change persona
du -sh ~/.claude/backups/                       # Check transcript backup size
find ~/.claude/backups/ -mtime +30 -delete      # Clean old transcripts manually
claude plugins update                           # Update plugins
```

## Credits

Built through iterative testing and refinement with Claude Code itself — patterns that survived contact with actual codebases, not theoretical best practices.

### Agent Plugins

**[agents](https://github.com/wshobson/agents)** by [Seth Hobson](https://github.com/wshobson) — 72 plugins providing 112+ specialist agents that make the 4-phase workflow possible. Without this project, there would be no architect review gate, no domain-specific routing, no code reviewer quality gate.

**[claude-code-plugins](https://github.com/anthropics/claude-code-plugins)** by Anthropic — official plugins:
- `context7` — real-time library documentation lookup
- `frontend-design` — UI/UX design quality for frontend work

### Tools

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) by Anthropic

## License

MIT
