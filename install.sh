#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Claude Code Blueprint — Installer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Installs the engineering blueprint to ~/.claude/
#
# What it does:
#   1. Backs up existing ~/.claude/CLAUDE.md and settings.json
#   2. Copies CLAUDE.md, rules files, hooks, and status line
#   3. Merges settings.json (hooks + status line + plugins)
#   4. Installs required plugins
#   5. Runs a health check to verify everything
#
# Usage:
#   chmod +x install.sh && ./install.sh
#
# To uninstall:
#   ./install.sh --uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
RST='\033[0m'

info()  { printf "${CYAN}[INFO]${RST} %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${RST}   %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${RST} %s\n" "$1"; }
fail()  { printf "${RED}[FAIL]${RST} %s\n" "$1"; }

# ── Uninstall ────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""
  echo -e "${BOLD}Uninstalling Claude Code Blueprint${RST}"
  echo "This will remove blueprint files but preserve your backups."
  echo ""
  read -p "Continue? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

  rm -f "$CLAUDE_DIR/CLAUDE.md"
  rm -rf "$CLAUDE_DIR/rules"
  rm -rf "$CLAUDE_DIR/hooks"
  rm -f "$CLAUDE_DIR/statusline-command.sh"

  # Restore backups if they exist
  for f in "$CLAUDE_DIR"/*.backup-*; do
    if [ -f "$f" ]; then
      original="${f%%.backup-*}"
      cp "$f" "$original"
      ok "Restored $(basename "$original") from backup"
    fi
  done

  ok "Blueprint uninstalled"
  exit 0
fi

# ── Pre-flight checks ───────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${BOLD}  Claude Code Blueprint — Installer${RST}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""

# Check for claude CLI
if ! command -v claude >/dev/null 2>&1; then
  fail "Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi
ok "Claude Code CLI found"

# Check for jq (required by hooks and status line)
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi
ok "jq found"

# ── Backup existing files ───────────────────────────────────
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

# ── Install CLAUDE.md ───────────────────────────────────────
echo ""
info "Installing CLAUDE.md and rules..."

cp "$SCRIPT_DIR/templates/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "Installed CLAUDE.md ($(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ') lines)"

for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
  cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  ok "Installed rules/$(basename "$rule_file")"
done

# ── Install hooks ────────────────────────────────────────────
echo ""
info "Installing hooks..."

for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
  cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  ok "Installed hooks/$(basename "$hook_file")"
done

# ── Install scripts ──────────────────────────────────────────
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

# ── Install status line ─────────────────────────────────────
echo ""
info "Installing status line..."

cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "Installed statusline-command.sh"

# ── Merge settings.json ─────────────────────────────────────
echo ""
info "Configuring settings.json..."

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  # Merge: keep existing settings, add/overwrite hooks + statusLine + plugins
  EXISTING="$CLAUDE_DIR/settings.json"
  TEMPLATE="$SCRIPT_DIR/templates/settings.json"

  # Deep merge using jq: template values override existing for hooks/statusLine/plugins
  jq -s '.[0] * .[1]' "$EXISTING" "$TEMPLATE" > "$CLAUDE_DIR/settings.json.tmp"
  mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
  ok "Merged settings.json (preserved existing settings, added blueprint config)"
else
  cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
  ok "Installed settings.json (fresh)"
fi

# ── Install plugins ──────────────────────────────────────────
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

# ── Health check ─────────────────────────────────────────────
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
  # Check plugin count
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

# ── Hook Smoke Tests ─────────────────────────────────────────
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

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Summary ━━━${RST}"
echo ""
if [ "$errors" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed. Blueprint installed successfully.${RST}"
  echo ""
  echo "Next steps:"
  echo "  1. Open a new Claude Code session: claude"
  echo "  2. Run /memory to verify files are loaded"
  echo "  3. Try a non-trivial task to test the workflow"
  echo ""
  echo "To customize for your project, create a project-level CLAUDE.md"
  echo "in your repo root. See examples/project-CLAUDE.md for a template."
else
  echo -e "${RED}${BOLD}$errors check(s) failed. Review errors above.${RST}"
  exit 1
fi