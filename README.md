<div align="center">

<img src=".github/cover.png" alt="Claude Code Forge" width="600">

<br>

**Stop prompting. Start engineering.**

Claude Code is powerful out of the box. But left unconfigured, it hallucinates structure,<br>
ignores long instructions, and treats every user the same. The forge fixes that.

[![Tests](https://github.com/nickt92/claude-code-forge/actions/workflows/test.yml/badge.svg)](https://github.com/nickt92/claude-code-forge/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.5.0-brightgreen?style=flat-square)](https://github.com/nickt92/claude-code-forge/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-informational?style=flat-square)](#quick-start)
[![Claude Code](https://img.shields.io/badge/Claude_Code-%E2%89%A51.0-blueviolet?style=flat-square)](https://docs.anthropic.com/en/docs/claude-code)
[![Personas](https://img.shields.io/badge/Personas-12-orange?style=flat-square)](#persona-system)
[![Plugins](https://img.shields.io/badge/Plugins-18-green?style=flat-square)](#credits)

**`forge` CLI** · **Desktop App (Beta)** · **12 Personas** · **3 Plugin Groups** · **3 Permission Presets** · **9 Hooks** · **8 Rules Files** · **966 Tests**

</div>

## The Problem

Claude Code reads instructions, but doesn't always follow them. Through empirical testing:

> **Long files lose adherence.** Content buried at line 200+ gets ignored. The forge assembles focused CLAUDE.md files under 200 lines, every time.

> **Passive language is treated as optional.** "Consider accessibility" is a suggestion. "Apply to ALL frontend work" is a command. The forge uses imperative, tested phrasing throughout.

> **Knowing the rules ≠ following them.** Hooks create forcing functions that block non-compliant behavior at write time, not just at read time.

> **One size doesn't fit all.** A product manager doesn't need tier classifications and agent names. A senior engineer does. Same quality standards, different communication.

## The Fix

**Persona-tuned instructions.** 12 personas, same quality standards. Claude speaks your language, whether you're a vibe coder or a CTO.

**Runtime enforcement.** 9 hooks that block mistakes at write time. Secret leaks, bad commits, unplanned architecture changes: caught before they land.

**Focused, tested CLAUDE.md.** Assembled under 200 lines from imperative, empirically-tested sections. No fluff. No ignored content.

## Quick Start

**Prerequisites:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), `jq` (`brew install jq`), macOS / Linux / Windows ([Git Bash](https://gitforwindows.org/))

```bash
git clone https://github.com/nickt92/claude-code-forge.git
cd claude-code-forge && ./install.sh      # Persona + permissions wizard

# Add forge to your PATH (add to ~/.zshrc or ~/.bashrc for persistence)
export PATH="$HOME/.claude/bin:$PATH"

forge doctor                               # Verify installation
```

## Persona System

Pick during install. Switch anytime with `forge switch`. Or build your own.

Every persona enforces the same quality standards. What changes is how Claude **talks to you**.

**Non-technical** | plain language, step-by-step guidance

| Persona | Communication Style |
|:--------|:-------------------|
| **Product Manager** | Business language, trade-off framing |
| **Executive** | High-level summaries, strategic context |
| **Vibe Coder** | Casual, minimal jargon, just results |

**Technical** | domain terminology, balanced guidance

| Persona | Communication Style |
|:--------|:-------------------|
| **Designer (UI/UX)** | Design-aware, accessibility context |
| **Data Analyst** | Analytical reasoning, data terminology |
| **Data Scientist** | Statistical/ML vocabulary |
| **Junior Developer** | Explanatory, more "why" behind decisions |
| **Hobbyist** | Approachable, patterns explained as they appear |

**Engineering** | expert shorthand, high autonomy, full workflow visible

| Persona | Communication Style |
|:--------|:-------------------|
| **Senior Engineer** | Peer-level, terse, leads with recommendations |
| **CTO / Architect** | Architectural framing, trade-off analysis |
| **DevOps / Platform** | Infra-native terminology, operational context |
| **Data Engineer** | Pipeline/systems vocabulary, engineering depth |

Or run `forge build` to create your own persona from the 4 behavioral axes.

## Highlights

### Works Your Way
12 personas from vibe coder to CTO. Same quality rules, your communication style. Or `forge build` to create your own.

### Enforces at Write Time
9 hooks block mistakes before they land: architect review gate, commit validator, secret filter, command guard, database guard, context guardian, and more.

### Scores and Fixes Your Config
`forge audit` scores your CLAUDE.md, detects gaps in sections/tech stack/hooks, and `--fix` auto-remediates findings. The desktop app surfaces everything visually.

### Scales With You
3 plugin groups (6 → 16 → 18), 3 permission presets (ask first → auto-edit → full autonomy), per-project config, document chain support.

### Desktop App (macOS, Beta)
Native menu bar app with dashboard, audit detail, hook telemetry, persona switcher, Claude-powered onboarding, and doctor diagnostics. Build from source if you clone the repo.

### 966 Tests
777 CLI (bats-core) + 189 Swift, cross-platform on every push via GitHub Actions.

## Status Line

A rich, 5-zone status line that shows everything about your Claude Code session at a glance:

```
🌿 feat/thing ✦3 ↑2 ║ 🧠 Opus ⬆ high 🤖 architect ║ ◈ ▐████████░░░░▌ 62% 💾 46% ║ 🔋 48% ⚡ 342t/s ║ 💰 $2.87 · ✏️ +342/−89 · ⏱️ 32m
```

| Zone | What It Shows |
|:-----|:-------------|
| **Git** | Branch, uncommitted changes, ahead/behind, stashes, rebase/merge state |
| **Model** | Active model with color-coded badge (Opus/Sonnet/Haiku), effort level, active subagent |
| **Context** | Gradient bar (blue→cyan→amber→red) with usage %, cache hit ratio |
| **Limits** | 5-hour and 7-day rate limits, token generation speed |
| **Session** | Name, cost, lines changed, duration, vim mode |

Run `forge statusline` for an interactive legend with every icon explained, or open **Settings → Statusline Guide** in the desktop app.

<details>
<summary><strong>CLI Reference</strong></summary>

The `forge` CLI is a command dispatcher. Each subcommand lives in `lib/cmd-<name>.sh` and is auto-discovered.

```
forge <command> [options]

Setup
  install     Install or reinstall forge to ~/.claude/
  build       Create a custom persona profile
  init        Initialize per-project forge config

Management
  switch      Switch to a different persona
  update      Update forge from source repository
  restore     Roll settings.json back to an earlier snapshot
  config      Get or set forge settings
  permissions Manage Claude Code permission presets

Diagnostics
  status      Show current installation status
  doctor      Run diagnostic health checks
  diff        Show differences between source and installed
  dashboard   Configuration health dashboard (JSON output)
  audit       Audit CLAUDE.md quality (--fix to auto-remediate)
  analyze     Extract codebase context as structured JSON

Info
  statusline  Interactive status line legend
  stats       Statistics, hook telemetry, session scorecard (--json)
  export      Package installation into portable tar.gz
  version     Show forge version
  help        Show this help
```

Run `forge <command> --help` for command-specific options.

### forge install

```bash
forge install                              # Interactive wizard
forge install --profile senior-engineer   # Non-interactive
forge install --plugins minimal           # Override plugin group
forge install --permissions full-autonomy # Set permission preset
forge install --reconfigure               # Re-run persona wizard
forge install --uninstall                 # Remove forge, restore backups
forge install --check                     # Health checks only (no changes)
forge install --dry-run --profile senior-engineer  # Preview without changes
forge install --quiet --profile vibe-coder  # Minimal output (CI-friendly)
```

### forge switch

Switch persona without a full reinstall. Reassembles CLAUDE.md and updates profile.json in seconds.

```bash
forge switch senior-engineer
forge switch vibe-coder
forge switch custom-my-team
forge switch                   # List available personas
```

### forge doctor

Diagnostic health checks across 6 categories: manifest, file integrity, hook configuration, CLAUDE.md, plugins, CLI.

```bash
forge doctor
forge doctor --json
```

### forge permissions

Three-tier permission presets controlling what Claude can do without prompting. Selected during install; change anytime with `forge permissions`.

```bash
forge permissions                          # Show current preset
forge permissions --preset full-autonomy   # Apply a preset
forge permissions --json
```

| Preset | Rules | What's Auto-Approved |
|:-------|------:|:---------------------|
| **Ask Before Changes** | 82 | File reading, code search, git inspection |
| **Auto-Edit** | 94 | Everything above + file creation/editing |
| **Full Autonomy** | 308 | Everything above + git, package managers, compilers, Docker, GitHub CLI |

All tiers exclude destructive operations. The command-guard hook provides runtime enforcement.

### Other Commands

- `forge update` | Pull latest, fast-forward merge, reinstall
- `forge status` / `forge status --json` | Current persona, version, hooks
- `forge diff` | Preview what update would change
- `forge build` | Interactive custom persona wizard
- `forge init` | Per-project Claude config (`.claude/CLAUDE.md` + rules)
- `forge config get|set <key>` | Get/set forge settings
- `forge dashboard` | JSON health dashboard (data source for desktop app)
- `forge analyze /path/to/repo --json` | Extract codebase context
- `forge audit /path/to/repo` | Audit CLAUDE.md quality (`--fix` to auto-remediate, `--json` for structured output)
- `forge stats` | Installation overview, security events, hook telemetry (`--json` for structured output)
- `forge export` | Package installation into portable tar.gz
- `forge statusline` | Interactive status line legend with all icons explained

</details>

<details>
<summary><strong>Plugin Groups</strong></summary>

Each persona has a default plugin group; override with `--plugins` at install time.

| Group | Plugins | Default for |
|:------|--------:|:------------|
| **full** | 18 | senior-engineer, cto-architect, devops-engineer, data-engineer, data-scientist |
| **standard** | 16 | analyst, junior-dev, designer (drops HR/legal and startup plugins) |
| **minimal** | 6 | vibe-coder, hobbyist, executive, product-manager |

```bash
forge install --profile senior-engineer --plugins standard
forge install --profile vibe-coder --plugins full
```

</details>

<details>
<summary><strong>What Gets Installed</strong></summary>

The forge writes only to `~/.claude/`. Existing configuration is backed up to `~/.claude/forge-backup/` before any changes.

```
~/.claude/
├── CLAUDE.md                     # Assembled from your persona
├── profile.json                  # Persona config (hooks read at runtime)
├── statusline-command.sh         # Status line script
├── settings.json                 # Forge hooks + plugins merged in
├── bin/forge -> <source>/forge   # Symlink, always current
├── rules/                        # 8 rules files
├── hooks/                        # 9 enforcement hooks
├── scripts/                      # Onboarding scripts
├── completions/                  # Bash + Zsh tab completion
├── profiles/                     # Custom personas (from forge build)
├── lib/ui.sh                     # Shared output library
└── forge-backup/                 # Pre-forge snapshot for clean uninstall
```

The symlink means `forge` is always current after `git pull`. Settings merge is additive: your existing hooks and plugins are never removed. Uninstall is clean and manifest-driven.

</details>

<details>
<summary><strong>Persona System Deep Dive</strong></summary>

The forge uses an **axis-based persona system** with 4 behavioral axes:

| Axis | Values | What It Controls |
|:-----|:-------|:----------------|
| **Communication** | `plain` · `technical` · `expert` | Jargon level, explanation depth |
| **Autonomy** | `guided` · `moderate` · `high` | How often Claude asks vs proceeds |
| **Workflow** | `simplified` · `standard` · `advanced` | Internal ceremony visibility |
| **Depth** | `conceptual` · `practical` · `engineering` | Code-level detail |

15 section files serve any number of personas without content drift. Adding a persona is one JSON file.

**Interpretation Directive** | For non-technical personas, Claude follows the same engineering rules internally but adapts communication:

| What happens internally | What the vibe coder sees |
|:------------------------|:-------------------------|
| "Significant-tier task, Phase 1 design gate" | "Here's my proposed approach" |
| "Invoking security-auditor agent" | "I'm reviewing this for security" |

Quality is identical. Jargon is not.

</details>

<details>
<summary><strong>4-Phase Workflow</strong></summary>

Every task follows a structured workflow, with rigor proportional to complexity:

```
Phase 1 - Design     (significant tasks only)
Phase 2 - Implement  (all tasks)
Phase 3 - Review     (all tasks, scope varies by tier)
Phase 4 - React      (on-demand: errors, incidents, debugging)
```

| Tier | Criteria | What Happens |
|:-----|:---------|:-------------|
| **Trivial** | Single-file, clear requirements | Implement directly, code review before commit |
| **Moderate** | Multi-file, well-understood domain | Implement, domain architect + code review |
| **Significant** | New service, auth, architecture | Plan mode → architect review → approval → implement |

</details>

<details>
<summary><strong>Hooks</strong></summary>

| Hook | Trigger | What It Does |
|:-----|:--------|:-------------|
| `session-init.sh` | First prompt per session | Task classification nudge adapted to autonomy level |
| `architect-gate.sh` | Write/Edit tools | Blocks plan files without `## Architect Review` section |
| `commit-validator.sh` | Bash tool (git commit) | Blocks AI attribution, warns on non-conventional format |
| `context-guardian.sh` | ExitPlanMode / PreCompact | Blocks compaction after plan approval, suggests `/clear` |
| `backup-transcript.sh` | Before compaction | Saves full transcript to `~/.claude/backups/` |
| `command-guard.sh` | Bash tool | Blocks destructive commands (`rm -rf /`, shell wrappers) |
| `secret-filter.sh` | After tool use | Detects credentials in output (API keys, JWTs, database URLs) |
| `db-guard.sh` | Bash tool (database CLIs) | Blocks destructive SQL (`DROP TABLE`, `DELETE` without `WHERE`) |
| `forge-update-check.sh` | First prompt per session | Advisory notice when forge version is outdated |

See [SECURITY.md](SECURITY.md) for the security model and known limitations.

</details>

<details>
<summary><strong>Status Line</strong></summary>

The status line has 5 zones with 20+ icons. Here's the full reference:

**Zone 1: Git** | 🌿 branch, 🌲 worktree, 📂 directory, ✦N dirty, ↑N ahead, ↓N behind, 📦N stashes, REBASING/MERGING/CHERRY-PICK state

**Zone 2: Model + Agent** | 🧠 model with colored badge (Opus=magenta, Sonnet=blue, Haiku=teal), ⬆/⬛/⬇ effort level, 🤖 active subagent

**Zone 3: Context Window** | ◈ marker, gradient bar (blue→cyan→amber→red), usage %, 💾 cache hit ratio, ⚠ 200k+ warning

**Zone 4: Limits + Speed** | 🔋 5-hour rate limit (green/yellow/red), 📅 7-day rate limit (shown >=50%), ⚡ token speed

**Zone 5: Session** | 📝 session name, 💰 cost, ✏️ lines +/-, ⏱️ duration, ◆ vim mode

**Colors:** green = all clear, yellow = attention, red = critical, bold = important values

Run `forge statusline` for a colorful interactive legend in the terminal.

</details>

<details>
<summary><strong>Project Onboarding</strong></summary>

### Desktop App

- **Existing projects:** Dashboard → "Generate CLAUDE.md" → streaming split-view analysis
- **New projects:** ⌘N → pick directory → describe project → Claude generates CLAUDE.md

### CLI

```bash
# Existing project: analyzes architecture, tech stack, patterns
cd /path/to/project && ~/.claude/scripts/generate-project-claude.sh

# New project: interactive setup with architectural decisions
mkdir my-project && cd my-project && git init && ~/.claude/scripts/init-project-claude.sh

# Per-project config (version-controlled)
forge init                             # Uses current persona
forge init --persona senior-engineer  # Specify persona
forge init --docs                     # Scaffold document chain
```

### Document Chain

For multi-phase projects, the forge supports structured context files:

```
your-project/
├── CLAUDE.md         # Project-level instructions
├── PROJECT.md        # Vision, goals, constraints
├── REQUIREMENTS.md   # Scoped requirements with acceptance criteria
└── ROADMAP.md        # Phased plan with progress tracking
```

</details>

<details>
<summary><strong>Desktop App (macOS, Beta)</strong></summary>

> **Beta:** The desktop app is functional but still under active development. Expect rough edges. It will ship as a packaged release in a future major version.

A native macOS menu bar app (SwiftUI, macOS 14+) with forge brand identity:

- **Menu bar icon** with animated score ring and aggregate health score
- **Dashboard** with searchable, filterable repository list and stagger animations
- **Repo detail view** with audit breakdown, quality gauge, hook compatibility, quick-fix actions
- **Hook telemetry** with invocation counts, block rate gauge, per-hook bar charts
- **Claude-powered onboarding** with streaming split-view UX
- **Persona switcher** to switch without terminal
- **Doctor view** for visual health diagnostics
- **Permission presets** with three-tier autonomy system
- **Setup wizard** for five-step onboarding
- **Statusline Guide** as visual legend (Settings > About > Statusline Guide)

The app shells out to the `forge` CLI and parses JSON. It does not duplicate CLI logic.

**Requirements:** macOS 14+, Xcode 15+, forge CLI installed

```bash
# Clone the repo (the app is not included in the CLI install)
git clone https://github.com/nickt92/claude-code-forge.git
cd claude-code-forge

# Build and run
cd app && xcodebuild -project ForgeDesktop.xcodeproj -scheme ForgeDesktop clean build

# The built app will be in DerivedData — or open ForgeDesktop.xcodeproj in Xcode and hit ⌘R
```

</details>

<details>
<summary><strong>Customization</strong></summary>

**Quality Standards** | Edit `templates/rules/quality-engineering.md` (coverage targets, accessibility, performance). Run `forge install` to propagate.

**Project-Level Overrides** | Copy `examples/project-CLAUDE.md` to your project root. Project-level instructions override global for project-specific concerns.

**Custom Agents** | Add agents to `templates/rules/agent-orchestration.md` and run `forge install`.

**Custom Personas** | `forge build` walks through axes, quality settings, and plugin group. Use immediately with `forge switch custom-<name>`.

</details>

<details>
<summary><strong>Troubleshooting</strong></summary>

**Health check fails** | Run `forge doctor`. Common causes: missing hooks (`forge install`), plugin count mismatch (retry install), version mismatch (`forge update`).

**Claude ignoring rules** | Run `/memory` to confirm files are loaded. Check: `~/.claude/CLAUDE.md` exists and is under 200 lines, `~/.claude/rules/` has 8 files, Claude Code >=1.0. Start a fresh session if context is stale.

**`forge: command not found`** | Add `export PATH="$HOME/.claude/bin:$PATH"` to your shell profile, or call `~/.claude/bin/forge` directly.

**architect-gate blocking** | Add `## Architect Review` section to your plan file. Only applies to files in `~/.claude/plans/`.

**commit-validator blocking** | Remove AI attribution (`Co-Authored-By: Claude`, etc.). Non-conventional format warnings are informational only.

**command-guard/db-guard blocking** | Tell Claude to proceed; it retries with a logged override. All overrides go to `~/.claude/security.log`. See [SECURITY.md](SECURITY.md).

**Existing hooks/plugins** | Settings merge is additive. Check `~/.claude/forge-backup/manifest.json` for exactly what was added.

**Colors broken (WSL/Linux)** | Use `NO_COLOR=1 forge install --profile senior-engineer`. Non-TTY environments auto-fallback to plain text.

</details>

<details>
<summary><strong>Testing</strong></summary>

966 automated tests across two suites, run on every push via GitHub Actions —
including release branches, and including the Swift suite.

**CLI (bats-core)** | 777 tests across macOS, Ubuntu, and Windows:

```bash
./test/run_tests.sh              # All tests
./test/run_tests.sh unit         # Hook and CLI unit tests
./test/run_tests.sh integration  # Assembly, merge, install flow
./test/run_tests.sh validation   # Profile schema, section coverage
```

| Suite | Files | Covers |
|:------|------:|:-------|
| **Unit** | 30 | Hooks, CLI, plugins, manifest, platform, UI, config, dashboard, stats (incl. JSON), export, permissions, audit |
| **Integration** | 13 | Assembly, settings merge/unmerge, install, backup/restore, switch, doctor, diff, update, build, init |
| **Validation** | 6 | Profile schema, section coverage, settings template, completions, bats namespace, README claims |

All tests run in a sandbox. Your real `~/.claude/` is never touched.

**Desktop (Swift)** | 189 tests (XCTest):

```bash
cd app/ForgeDesktopCore && swift test
```

</details>

<details>
<summary><strong>Design Decisions</strong></summary>

- **Why a forge CLI?** `install.sh` flags became unmanageable. The CLI groups operations, provides per-command `--help`, and is extensible (one file per command).
- **Why a native desktop app?** Always-on via menu bar, instant launch, first-class macOS citizen. CLI remains the cross-platform interface.
- **Why shell out from the app?** Single source of truth. CLI gains capabilities, app gets them for free.
- **Why a symlink?** `forge` is always current after `git pull`, no reinstall needed.
- **Why plugin groups?** 18 plugins is right for engineering, excessive for a vibe coder.
- **Why hooks over instructions?** Instructions suggest. Hooks enforce.
- **Why under 200 lines?** Anthropic recommends it. Testing confirmed content past line 200 gets ignored.
- **Why axis-based personas?** 15 section files serve unlimited personas. One JSON file per persona.
- **Why manifest-based backups?** Single snapshot, no accumulation, surgical uninstall.

</details>

<details>
<summary><strong>Maintenance</strong></summary>

```bash
forge status          # Persona, version, hooks
forge stats           # Security events, backup metrics
forge doctor          # Health check
forge diff            # Preview changes
forge update          # Pull latest and reinstall
forge switch <name>   # Change persona
forge export          # Portable archive
forge install --check # Health checks only
```

</details>

## Credits

Built through iterative testing and refinement with Claude Code itself. Patterns that survived contact with actual codebases, not theoretical best practices.

### Shoutout: Seth Hobson

The forge's 4-phase workflow runs on **[agents](https://github.com/wshobson/agents)** by [Seth Hobson](https://github.com/wshobson). 72 plugins, 112+ specialist agents. The architect review gate, domain-specific routing, code reviewer quality gate: none of it would exist without this project. If you're using the forge, you're using Seth's work on every task.

### Other Credits

**[claude-plugins-official](https://github.com/anthropics/claude-plugins-official)** by Anthropic | `context7` (library docs) and `frontend-design` (UI/UX quality)

**[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** by Anthropic

## License

MIT
