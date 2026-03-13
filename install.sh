#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Claude Code Forge — Installer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Installs Claude Code Forge to ~/.claude/
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
#   ./install.sh --quiet --profile senior-engineer
#   ./install.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SECTIONS_DIR="$SCRIPT_DIR/templates/sections"
PROFILES_DIR="$SCRIPT_DIR/templates/profiles"

# Source libraries
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/assembly.sh"
source "$SCRIPT_DIR/lib/settings-merge.sh"
source "$SCRIPT_DIR/lib/backup.sh"

# ── Health Check Function ─────────────────────────────────────
# Callable standalone via --check or at end of install flow.
run_health_checks() {
  step "Verifying installation"

  local errors=0
  local health_pass=0
  local health_fail=0
  debug "starting health checks"

  # CLAUDE.md
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    ((health_pass++))
  else
    fail "CLAUDE.md missing"; ((health_fail++)); ((errors++))
  fi

  # profile.json
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    ((health_pass++))
  else
    fail "profile.json missing"; ((health_fail++)); ((errors++))
  fi

  # Rules files
  for rule in quality-engineering agent-orchestration commit-and-delivery context-and-memory pull-requests project-setup scope-discipline; do
    if [ -f "$CLAUDE_DIR/rules/${rule}.md" ]; then
      ((health_pass++))
    else
      fail "rules/${rule}.md missing"; ((health_fail++)); ((errors++))
    fi
  done

  # Hooks
  for hook in session-init architect-gate backup-transcript commit-validator; do
    if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ] && [ -x "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
      ((health_pass++))
    else
      fail "hooks/${hook}.sh missing or not executable"; ((health_fail++)); ((errors++))
    fi
  done

  # Status line
  if [ -f "$CLAUDE_DIR/statusline-command.sh" ] && [ -x "$CLAUDE_DIR/statusline-command.sh" ]; then
    ((health_pass++))
  else
    fail "statusline-command.sh missing or not executable"; ((health_fail++)); ((errors++))
  fi

  # Settings checks
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if jq -e '.hooks' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
      ((health_pass++))
    else
      fail "settings.json missing hooks configuration"; ((health_fail++)); ((errors++))
    fi
    if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
      ((health_pass++))
    else
      fail "settings.json missing status line configuration"; ((health_fail++)); ((errors++))
    fi
    local plugin_count
    plugin_count=$(jq -r '.enabledPlugins // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
    if [ "$plugin_count" -ge 15 ]; then
      ((health_pass++))
    elif [ "$plugin_count" -gt 0 ]; then
      warn "Only $plugin_count plugins enabled (expected 18)"; ((health_fail++))
    else
      fail "No plugins enabled in settings.json"; ((health_fail++)); ((errors++))
    fi
  else
    fail "settings.json missing"; ((health_fail++)); ((errors++))
  fi

  debug "health checks complete (pass=$health_pass fail=$health_fail)"

  # Assembly smoke test — count silently, print only failures
  debug "starting assembly smoke tests"
  local assembly_pass=0
  local assembly_fail=0
  local persona_key temp_output line_count
  for profile_json in "$PROFILES_DIR"/*.json; do
    persona_key=$(jq -r '.persona' "$profile_json")
    temp_output="$(get_temp_dir)/claude-forge-test-${persona_key}.md"
    if assemble_claude_md "$profile_json" "$temp_output" 2>/dev/null; then
      line_count=$(wc -l < "$temp_output" | tr -d ' ')
      if [ "$line_count" -le 200 ]; then
        ((assembly_pass++))
      else
        warn "${persona_key}: ${line_count} lines (over 200 limit)"
        ((assembly_fail++))
      fi
      rm -f "$temp_output"
    else
      fail "${persona_key}: assembly failed"
      ((assembly_fail++)); ((errors++))
    fi
  done

  local total_checks=$(( health_pass + health_fail + assembly_pass + assembly_fail ))
  local total_pass=$(( health_pass + assembly_pass ))

  if [ "$errors" -eq 0 ] && [ "$health_fail" -eq 0 ] && [ "$assembly_fail" -eq 0 ]; then
    ok "All checks passed (${health_pass} health, ${assembly_pass} assemblies)"
  else
    if [ "$health_fail" -gt 0 ] || [ "$assembly_fail" -gt 0 ]; then
      ok "${total_pass}/${total_checks} checks passed"
    fi
  fi

  return "$errors"
}

# ── Help text ────────────────────────────────────────────────
show_help() {
  cat <<'EOF'
Claude Code Forge — Installer

Usage:
  ./install.sh                         Interactive wizard
  ./install.sh --profile <name>        Non-interactive install
  ./install.sh --reconfigure           Re-run the persona wizard
  ./install.sh --uninstall             Remove forge files (restores backups)
  ./install.sh --check                  Run health checks only (no install)
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
EOF
  exit 0
}

# ── Parse arguments ───────────────────────────────────────────
PROFILE_ARG=""
RECONFIGURE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      ;;
    --quiet|-q)
      export UI_QUIET=true
      shift
      ;;
    --debug)
      export UI_DEBUG=true
      shift
      ;;
    --check)
      RUN_CHECK_ONLY=true
      shift
      ;;
    --uninstall)
      # Require jq for manifest-based uninstall
      if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required for uninstall. Install: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
      fi

      banner "Claude Code Forge — Uninstall"
      echo ""
      show_uninstall_preview
      read -p "Continue? (y/N) " -n 1 -r
      echo
      [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

      uninstall_forge

      # Offer plugin uninstall
      echo ""
      read -p "Also uninstall forge plugins? (y/N) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] && command -v claude >/dev/null 2>&1; then
        for plugin in \
          "wshobson/claude-code-workflows:backend-development" \
          "wshobson/claude-code-workflows:documentation-generation" \
          "wshobson/claude-code-workflows:debugging-toolkit" \
          "wshobson/claude-code-workflows:frontend-mobile-development" \
          "wshobson/claude-code-workflows:full-stack-orchestration" \
          "wshobson/claude-code-workflows:tdd-workflows" \
          "wshobson/claude-code-workflows:code-refactoring" \
          "wshobson/claude-code-workflows:dependency-management" \
          "wshobson/claude-code-workflows:error-debugging" \
          "wshobson/claude-code-workflows:javascript-typescript" \
          "wshobson/claude-code-workflows:cicd-automation" \
          "wshobson/claude-code-workflows:cloud-infrastructure" \
          "wshobson/claude-code-workflows:hr-legal-compliance" \
          "wshobson/claude-code-workflows:database-design" \
          "wshobson/claude-code-workflows:startup-business-analyst" \
          "wshobson/claude-code-workflows:comprehensive-review" \
          "anthropics/claude-code-plugins:context7" \
          "anthropics/claude-code-plugins:frontend-design"; do
          claude plugins remove "$plugin" </dev/null 2>/dev/null || true
        done
        ok "Plugins removed"
      fi

      exit 0
      ;;
    --profile)
      if [[ $# -lt 2 ]]; then
        fail "Missing profile name after --profile"
        echo "Usage: ./install.sh --profile <name>"
        exit 1
      fi
      PROFILE_ARG="$2"
      shift 2
      ;;
    --reconfigure)
      RECONFIGURE=true
      shift
      ;;
    *)
      fail "Unknown option: $1"
      echo "Usage: ./install.sh [--profile <name>] [--reconfigure] [--uninstall] [--quiet] [--help]"
      exit 1
      ;;
  esac
done

# ── Check-only mode (runs health checks without installing) ──
if [ "${RUN_CHECK_ONLY:-}" = true ]; then
  banner "Claude Code Forge — Health Check"
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    info "Profile: $(jq -r '.label' "$CLAUDE_DIR/profile.json" 2>/dev/null)"
  fi
  run_health_checks
  exit $?
fi

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
  banner "Claude Code Forge — Setup"
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
      printf "  ${_C_BOLD}%2d.${_C_RST}  %-35s ${_C_DIM}%s${_C_RST}\n" "$i" "$label" "$description"
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

# ── Pre-flight checks ────────────────────────────────────────
if [ -z "$PROFILE_ARG" ] && [ "$RECONFIGURE" = false ]; then
  # Check if already configured — skip wizard on fresh install only
  if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    existing_persona=$(jq -r '.persona' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "")
    if [ -n "$existing_persona" ]; then
      banner "Claude Code Forge — Installer"
      echo ""
      existing_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "$existing_persona")
      info "Existing profile detected: ${existing_label}"
      echo ""
      echo "  1. Keep current profile and update forge files"
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
  local_label=$(jq -r '.label' "$PROFILES_DIR/${SELECTED_PERSONA}.json")
  banner "Claude Code Forge — Installer"
  info "Profile: ${local_label}"
else
  # --reconfigure: always run wizard
  run_wizard
fi

PROFILE_FILE="$PROFILES_DIR/${SELECTED_PERSONA}.json"

# ── Prerequisites ─────────────────────────────────────────────
step "Checking prerequisites"

prereq_ok=true
if ! command -v claude >/dev/null 2>&1; then
  fail "Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code"
  prereq_ok=false
fi
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
  prereq_ok=false
fi
if ! check_platform 2>/dev/null; then
  fail "Unsupported platform"
  prereq_ok=false
fi

if [ "$prereq_ok" = false ]; then
  exit 1
fi
ok "All prerequisites met (claude, jq, $(detect_platform))"

# ── Backup existing files ────────────────────────────────────
step "Backing up configuration"

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/backups"

# Migrate legacy .backup-* files if present
if has_legacy_backups; then
  migrate_legacy_backups
fi

# Snapshot pre-existing state (no-op on re-install)
snapshot_pre_install_state
ok "Backup complete (forge-backup/manifest.json)"

# ── Assemble and install CLAUDE.md ───────────────────────────
step "Assembling CLAUDE.md"

assemble_claude_md "$PROFILE_FILE" "$CLAUDE_DIR/CLAUDE.md"

lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
if [ "$lines" -le 200 ]; then
  ok "CLAUDE.md assembled ($lines lines)"
else
  warn "CLAUDE.md is $lines lines (target: under 200) — consider trimming sections"
fi

# Save profile.json for future reference
cp "$PROFILE_FILE" "$CLAUDE_DIR/profile.json"

# ── Install forge files ──────────────────────────────────────
step "Installing forge files"

rule_count=0
for rule_file in "$SCRIPT_DIR/templates/rules/"*.md; do
  cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
  ((rule_count++))
done

hook_count=0
for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
  cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
  ((hook_count++))
done

script_count=0
mkdir -p "$CLAUDE_DIR/scripts"
for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
  if [ -f "$script_file" ]; then
    cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    chmod +x "$CLAUDE_DIR/scripts/$(basename "$script_file")"
    ((script_count++))
  fi
done

cp "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

# Install ui.sh to ~/.claude/lib/
mkdir -p "$CLAUDE_DIR/lib"
cp "$SCRIPT_DIR/lib/ui.sh" "$CLAUDE_DIR/lib/ui.sh"

ok "${rule_count} rules, ${hook_count} hooks, ${script_count} scripts, statusline installed"

# ── Merge settings.json ──────────────────────────────────────
step "Configuring settings"

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  EXISTING="$CLAUDE_DIR/settings.json"
  TEMPLATE="$SCRIPT_DIR/templates/settings.json"

  # Migration: replace prompt-classifier with session-init
  if jq -e '.hooks.UserPromptSubmit[]? | select(.hooks[]?.command | contains("prompt-classifier"))' "$EXISTING" >/dev/null 2>&1; then
    jq '(.hooks.UserPromptSubmit // []) |= map(select(.hooks[]?.command | contains("prompt-classifier") | not))' "$EXISTING" > "$EXISTING.migrated"
    mv "$EXISTING.migrated" "$EXISTING"
  fi
  rm -f "$CLAUDE_DIR/hooks/prompt-classifier.sh"

  # Additive merge: combine hooks arrays, merge plugins objects, preserve user settings
  merge_settings "$EXISTING" "$TEMPLATE" "$CLAUDE_DIR/settings.json.tmp"
  mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
  ok "Settings merged (preserved existing config)"
else
  cp "$SCRIPT_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
  ok "Settings installed (fresh)"
fi

# ── Update manifest with installed files ──────────────────────
update_manifest_installed "$(jq -r '.persona' "$PROFILE_FILE")"

# ── Install plugins ───────────────────────────────────────────
step "Installing plugins"

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
debug "installing ${#PLUGINS[@]} plugins"
progress_start "${#PLUGINS[@]}" "Installing plugins"
for plugin in "${PLUGINS[@]}"; do
  if claude plugins add "$plugin" </dev/null 2>/dev/null; then
    ((installed++))
  else
    ((failed++))
  fi
  progress_tick
done

if [ "$failed" -eq 0 ]; then
  progress_done "$installed plugins installed"
else
  progress_done "$installed plugins installed ($failed skipped)"
fi

# Reset terminal state — claude CLI (Node.js) may dirty the tty on failure
stty sane < /dev/tty 2>/dev/null || true

# ── Verify installation (end of install flow) ────────────────
run_health_checks
check_errors=$?

# ── Summary ───────────────────────────────────────────────────
if [ "$check_errors" -eq 0 ]; then
  persona_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json")
  md_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
  success_banner "$persona_label" "$md_lines"
else
  fail_banner "$check_errors"
  exit 1
fi
