#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Claude Code Blueprint — Installer v2
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Installs the engineering blueprint to ~/.claude/
#
# What it does:
#   1. Runs onboarding wizard (or uses --profile flag)
#   2. Assembles a persona-tuned CLAUDE.md from section files
#   3. Backs up existing configuration
#   4. Copies rules files, hooks, and status line
#   5. Merges settings.json (hooks + status line + plugins)
#   6. Installs required plugins
#   7. Runs a health check to verify everything
#
# Usage:
#   chmod +x install.sh && ./install.sh
#   ./install.sh --profile senior-engineer
#   ./install.sh --reconfigure
#   ./install.sh --uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"
SECTIONS_DIR="$SCRIPT_DIR/templates/sections"
PROFILES_DIR="$SCRIPT_DIR/templates/profiles"

# Source platform utilities
source "$SCRIPT_DIR/lib/platform.sh"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

info()  { printf "${CYAN}[INFO]${RST} %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${RST}   %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${RST} %s\n" "$1"; }
fail()  { printf "${RED}[FAIL]${RST} %s\n" "$1"; }

# ── Parse arguments ───────────────────────────────────────────
PROFILE_ARG=""
RECONFIGURE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      echo ""
      echo -e "${BOLD}Uninstalling Claude Code Blueprint${RST}"
      echo "This will remove blueprint files but preserve your backups."
      echo ""
      read -p "Continue? (y/N) " -n 1 -r
      echo
      [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

      rm -f "$CLAUDE_DIR/CLAUDE.md"
      rm -f "$CLAUDE_DIR/profile.json"
      rm -rf "$CLAUDE_DIR/rules"
      rm -rf "$CLAUDE_DIR/hooks"
      rm -f "$CLAUDE_DIR/statusline-command.sh"

      for f in "$CLAUDE_DIR"/*.backup-*; do
        if [ -f "$f" ]; then
          original="${f%%.backup-*}"
          cp "$f" "$original"
          ok "Restored $(basename "$original") from backup"
        fi
      done

      ok "Blueprint uninstalled"
      exit 0
      ;;
    --profile)
      PROFILE_ARG="$2"
      shift 2
      ;;
    --reconfigure)
      RECONFIGURE=true
      shift
      ;;
    *)
      fail "Unknown option: $1"
      echo "Usage: ./install.sh [--profile <name>] [--reconfigure] [--uninstall]"
      exit 1
      ;;
  esac
done

# ── Persona definitions (for wizard display) ──────────────────
# Order matches profile filenames — wizard number = array index + 1
PERSONA_KEYS=(
  product-manager
  executive
  designer
  analyst
  data-scientist
  data-engineer
  junior-dev
  senior-engineer
  cto-architect
  devops-engineer
  vibe-coder
  hobbyist
)

# ── Onboarding wizard ────────────────────────────────────────
run_wizard() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
  echo -e "${BOLD}  Claude Code Blueprint — Setup${RST}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
  echo ""
  echo "What best describes your role?"
  echo ""

  local i=1
  for key in "${PERSONA_KEYS[@]}"; do
    local profile_file="$PROFILES_DIR/${key}.json"
    if [ -f "$profile_file" ]; then
      local label description
      label=$(jq -r '.label' "$profile_file")
      description=$(jq -r '.description' "$profile_file")
      printf "  ${BOLD}%2d.${RST}  %-35s ${DIM}%s${RST}\n" "$i" "$label" "$description"
    fi
    ((i++))
  done

  echo ""
  while true; do
    read -p "Your choice [1-${#PERSONA_KEYS[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PERSONA_KEYS[@]}" ]; then
      SELECTED_PERSONA="${PERSONA_KEYS[$((choice - 1))]}"
      break
    else
      echo "Please enter a number between 1 and ${#PERSONA_KEYS[@]}"
    fi
  done

  local selected_label
  selected_label=$(jq -r '.label' "$PROFILES_DIR/${SELECTED_PERSONA}.json")
  echo ""
  ok "Selected: ${selected_label}"
}

# ── Assemble CLAUDE.md from sections ─────────────────────────
assemble_claude_md() {
  local profile_file="$1"
  local output_file="$2"

  local comm auto work
  comm=$(jq -r '.axes.communication' "$profile_file")
  auto=$(jq -r '.axes.autonomy' "$profile_file")
  work=$(jq -r '.axes.workflow' "$profile_file")

  # Read quality array
  local quals
  quals=$(jq -r '.quality[]' "$profile_file")

  # Assemble by concatenating section files
  {
    cat "$SECTIONS_DIR/base.md"
    echo ""
    cat "$SECTIONS_DIR/communication-${comm}.md"
    echo ""
    cat "$SECTIONS_DIR/autonomy-${auto}.md"
    echo ""
    cat "$SECTIONS_DIR/workflow-${work}.md"
    echo ""
    cat "$SECTIONS_DIR/quality-core.md"
    for q in $quals; do
      if [ "$q" != "core" ] && [ -f "$SECTIONS_DIR/quality-${q}.md" ]; then
        echo ""
        cat "$SECTIONS_DIR/quality-${q}.md"
      fi
    done
  } > "$output_file"
}

# ── Pre-flight checks ────────────────────────────────────────
if [ -z "$PROFILE_ARG" ] && [ "$RECONFIGURE" = false ]; then
  # Check if already configured — skip wizard on fresh install only
  if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    existing_persona=$(jq -r '.persona' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "")
    if [ -n "$existing_persona" ]; then
      echo ""
      echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
      echo -e "${BOLD}  Claude Code Blueprint — Installer${RST}"
      echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
      echo ""
      existing_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "$existing_persona")
      info "Existing profile detected: ${existing_label}"
      echo ""
      echo "  1. Keep current profile and update blueprint files"
      echo "  2. Choose a new profile"
      echo "  3. Cancel"
      echo ""
      read -p "Your choice [1-3]: " update_choice
      case "$update_choice" in
        1)
          SELECTED_PERSONA="$existing_persona"
          ;;
        2)
          run_wizard
          ;;
        *)
          echo "Cancelled."
          exit 0
          ;;
      esac
    else
      run_wizard
    fi
  else
    run_wizard
  fi
elif [ -n "$PROFILE_ARG" ]; then
  # --profile flag: validate and use directly
  if [ ! -f "$PROFILES_DIR/${PROFILE_ARG}.json" ]; then
    fail "Unknown profile: ${PROFILE_ARG}"
    echo ""
    echo "Available profiles:"
    for key in "${PERSONA_KEYS[@]}"; do
      echo "  - $key"
    done
    exit 1
  fi
  SELECTED_PERSONA="$PROFILE_ARG"
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
  echo -e "${BOLD}  Claude Code Blueprint — Installer${RST}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
  echo ""
  local_label=$(jq -r '.label' "$PROFILES_DIR/${SELECTED_PERSONA}.json")
  ok "Using profile: ${local_label}"
else
  # --reconfigure: always run wizard
  run_wizard
fi

PROFILE_FILE="$PROFILES_DIR/${SELECTED_PERSONA}.json"

# Check for claude CLI
echo ""
if ! command -v claude >/dev/null 2>&1; then
  fail "Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi
ok "Claude Code CLI found"

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi
ok "jq found"

# Check platform
check_platform || exit 1

# ── Backup existing files ────────────────────────────────────
echo ""
info "Backing up existing configuration..."

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/backups"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md${BACKUP_SUFFIX}"
  ok "Backed up CLAUDE.md"
fi

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json${BACKUP_SUFFIX}"
  ok "Backed up settings.json"
fi

if [ -f "$CLAUDE_DIR/profile.json" ]; then
  cp "$CLAUDE_DIR/profile.json" "$CLAUDE_DIR/profile.json${BACKUP_SUFFIX}"
  ok "Backed up profile.json"
fi

# ── Assemble and install CLAUDE.md ───────────────────────────
echo ""
info "Assembling CLAUDE.md for persona: $(jq -r '.label' "$PROFILE_FILE")..."

assemble_claude_md "$PROFILE_FILE" "$CLAUDE_DIR/CLAUDE.md"

lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
if [ "$lines" -le 200 ]; then
  ok "Installed CLAUDE.md ($lines lines, under 200 limit)"
else
  warn "CLAUDE.md is $lines lines (target: under 200) — consider trimming sections"
fi

# Save profile.json for future reference
cp "$PROFILE_FILE" "$CLAUDE_DIR/profile.json"
ok "Saved profile.json ($(jq -r '.persona' "$PROFILE_FILE"))"

# ── Install rules files ──────────────────────────────────────
echo ""
info "Installing rules..."

for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
  cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  ok "Installed rules/$(basename "$rule_file")"
done

# ── Install hooks ─────────────────────────────────────────────
echo ""
info "Installing hooks..."

for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
  cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  ok "Installed hooks/$(basename "$hook_file")"
done

# ── Install scripts ───────────────────────────────────────────
echo ""
info "Installing scripts..."

mkdir -p "$CLAUDE_DIR/scripts"
for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
  if [ -f "$script_file" ]; then
    cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    chmod +x "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    ok "Installed scripts/$(basename "$script_file")"
  fi
done

# ── Install status line ──────────────────────────────────────
echo ""
info "Installing status line..."

cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "Installed statusline-command.sh"

# ── Merge settings.json ──────────────────────────────────────
echo ""
info "Configuring settings.json..."

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  EXISTING="$CLAUDE_DIR/settings.json"
  TEMPLATE="$SCRIPT_DIR/templates/settings.json"
  jq -s '.[0] * .[1]' "$EXISTING" "$TEMPLATE" > "$CLAUDE_DIR/settings.json.tmp"
  mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
  ok "Merged settings.json (preserved existing settings, added blueprint config)"
else
  cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
  ok "Installed settings.json (fresh)"
fi

# ── Install plugins ───────────────────────────────────────────
echo ""
info "Installing plugins (this may take a moment)..."

PLUGINS=(
  "wshobson/claude-code-workflows:backend-development"
  "wshobson/claude-code-workflows:documentation-generation"
  "wshobson/claude-code-workflows:debugging-toolkit"
  "wshobson/claude-code-workflows:frontend-mobile-development"
  "wshobson/claude-code-workflows:full-stack-orchestration"
  "wshobson/claude-code-workflows:tdd-workflows"
  "wshobson/claude-code-workflows:code-refactoring"
  "wshobson/claude-code-workflows:dependency-management"
  "wshobson/claude-code-workflows:error-debugging"
  "wshobson/claude-code-workflows:javascript-typescript"
  "wshobson/claude-code-workflows:cicd-automation"
  "wshobson/claude-code-workflows:cloud-infrastructure"
  "wshobson/claude-code-workflows:hr-legal-compliance"
  "wshobson/claude-code-workflows:database-design"
  "wshobson/claude-code-workflows:startup-business-analyst"
  "wshobson/claude-code-workflows:comprehensive-review"
  "anthropics/claude-code-plugins:context7"
  "anthropics/claude-code-plugins:frontend-design"
)

installed=0
failed=0
for plugin in "${PLUGINS[@]}"; do
  if claude plugins add "$plugin" 2>/dev/null; then
    ((installed++))
  else
    warn "Failed to install: $plugin (may already be installed)"
    ((failed++))
  fi
done
ok "Installed $installed plugins ($failed skipped/failed)"

# ── Health check ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Health Check ━━━${RST}"
echo ""

errors=0

# Check CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
  if [ "$lines" -le 200 ]; then
    ok "CLAUDE.md exists ($lines lines, under 200 limit)"
  else
    warn "CLAUDE.md is $lines lines (recommended: under 200)"
  fi
else
  fail "CLAUDE.md missing"; ((errors++))
fi

# Check profile.json
if [ -f "$CLAUDE_DIR/profile.json" ]; then
  persona_name=$(jq -r '.persona' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "unknown")
  ok "profile.json exists (persona: $persona_name)"
else
  fail "profile.json missing"; ((errors++))
fi

# Check rules files
for rule in quality-engineering agent-orchestration commit-and-delivery context-and-memory pull-requests; do
  if [ -f "$CLAUDE_DIR/rules/${rule}.md" ]; then
    ok "rules/${rule}.md exists"
  else
    fail "rules/${rule}.md missing"; ((errors++))
  fi
done

# Check hooks
for hook in prompt-classifier architect-gate backup-transcript; do
  if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ] && [ -x "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
    ok "hooks/${hook}.sh exists and executable"
  else
    fail "hooks/${hook}.sh missing or not executable"; ((errors++))
  fi
done

# Check status line
if [ -f "$CLAUDE_DIR/statusline-command.sh" ] && [ -x "$CLAUDE_DIR/statusline-command.sh" ]; then
  ok "statusline-command.sh exists and executable"
else
  fail "statusline-command.sh missing or not executable"; ((errors++))
fi

# Check settings.json has hooks
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  if jq -e '.hooks' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
    ok "settings.json has hooks configured"
  else
    fail "settings.json missing hooks configuration"; ((errors++))
  fi
  if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
    ok "settings.json has status line configured"
  else
    fail "settings.json missing status line configuration"; ((errors++))
  fi
  plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  if [ "$plugin_count" -ge 15 ]; then
    ok "settings.json has $plugin_count plugins enabled"
  elif [ "$plugin_count" -gt 0 ]; then
    warn "Only $plugin_count plugins enabled (expected 18). Run: claude plugins update"
  else
    fail "No plugins enabled in settings.json"; ((errors++))
  fi
else
  fail "settings.json missing"; ((errors++))
fi

# ── Hook Smoke Tests ──────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Hook Smoke Tests ━━━${RST}"
echo ""

# Test prompt-classifier: should detect "auth" as significant
classifier_output=$(echo '{"prompt":"Add new auth middleware"}' | bash "$CLAUDE_DIR/hooks/prompt-classifier.sh" 2>/dev/null)
if echo "$classifier_output" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; then
  ok "prompt-classifier detects significant keywords"
else
  fail "prompt-classifier did not detect 'auth' as significant"; ((errors++))
fi

# Test prompt-classifier: should NOT fire on trivial prompts
trivial_output=$(echo '{"prompt":"Fix a typo in the readme"}' | bash "$CLAUDE_DIR/hooks/prompt-classifier.sh" 2>/dev/null)
if [ -z "$trivial_output" ]; then
  ok "prompt-classifier ignores trivial prompts"
else
  warn "prompt-classifier fired on a trivial prompt (false positive)"
fi

# Test architect-gate: should block plan file without Architect Review
gate_output=$(printf '{"tool_input":{"file_path":"/tmp/.claude/plans/test.md","content":"# Plan\\nJust a plan"}}' | bash "$CLAUDE_DIR/hooks/architect-gate.sh" 2>&1)
gate_exit=$?
if [ "$gate_exit" -eq 2 ]; then
  ok "architect-gate blocks plan files without Architect Review"
else
  fail "architect-gate did not block incomplete plan file (exit: $gate_exit)"; ((errors++))
fi

# Test architect-gate: should allow plan file WITH Architect Review
gate_ok_output=$(printf '{"tool_input":{"file_path":"/tmp/.claude/plans/test.md","content":"# Plan\\n## Architect Review\\nApproved"}}' | bash "$CLAUDE_DIR/hooks/architect-gate.sh" 2>&1)
gate_ok_exit=$?
if [ "$gate_ok_exit" -eq 0 ]; then
  ok "architect-gate allows plan files with Architect Review"
else
  fail "architect-gate blocked a valid plan file (exit: $gate_ok_exit)"; ((errors++))
fi

# ── Assembly Smoke Test ───────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Assembly Smoke Test ━━━${RST}"
echo ""

assembly_errors=0
for profile_json in "$PROFILES_DIR"/*.json; do
  persona_key=$(jq -r '.persona' "$profile_json")
  temp_output="$(get_temp_dir)/claude-blueprint-test-${persona_key}.md"
  if assemble_claude_md "$profile_json" "$temp_output" 2>/dev/null; then
    line_count=$(wc -l < "$temp_output" | tr -d ' ')
    if [ "$line_count" -le 200 ]; then
      ok "  ${persona_key}: ${line_count} lines"
    else
      warn "  ${persona_key}: ${line_count} lines (over 200 limit)"
      ((assembly_errors++))
    fi
    rm -f "$temp_output"
  else
    fail "  ${persona_key}: assembly failed"
    ((assembly_errors++))
  fi
done

if [ "$assembly_errors" -eq 0 ]; then
  ok "All 12 persona assemblies under 200 lines"
else
  warn "$assembly_errors persona(s) had assembly issues"
  ((errors += assembly_errors))
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Summary ━━━${RST}"
echo ""
if [ "$errors" -eq 0 ]; then
  persona_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json")
  echo -e "${GREEN}${BOLD}All checks passed. Blueprint installed successfully.${RST}"
  echo ""
  echo "  Profile:  ${persona_label}"
  echo "  CLAUDE.md: $(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ') lines"
  echo ""
  echo "Next steps:"
  echo "  1. Open a new Claude Code session: claude"
  echo "  2. Run /memory to verify files are loaded"
  echo "  3. Try a non-trivial task to test the workflow"
  echo ""
  echo "To change your profile later: ./install.sh --reconfigure"
  echo "To customize for your project, create a project-level CLAUDE.md"
  echo "in your repo root. See examples/project-CLAUDE.md for a template."
else
  echo -e "${RED}${BOLD}$errors check(s) failed. Review errors above.${RST}"
  exit 1
fi