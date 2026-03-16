#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-wizard — persona selection, banners, and help
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Sourced by cmd-install.sh. Requires ui.sh and PROFILES_DIR.

# ── Persona definitions (for wizard display) ──────────────────
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
_install_run_wizard() {
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

# ── Install-specific banners ─────────────────────────────────

_install_success_banner() {
  local profile="$1"
  local lines="$2"
  _ui_quiet && return 0
  printf "\n🍺  ${_C_BOLD}Forge complete!${_C_RST}\n"
  kv "Profile" "$profile"
  kv "CLAUDE.md" "$lines lines"
  printf "\n${_C_BOLD}Next steps:${_C_RST}\n"
  printf "  ${_C_DIM}1.${_C_RST} Start a session: ${_C_BOLD}claude${_C_RST}\n"
  printf "  ${_C_DIM}2.${_C_RST} Run ${_C_BOLD}/memory${_C_RST} to verify\n"
  printf "  ${_C_DIM}3.${_C_RST} Init a project: ${_C_BOLD}forge init${_C_RST}\n"
  printf "\n${_C_DIM}  forge doctor        Health check\n"
  printf "  forge switch <p>    Switch persona\n"
  printf "  forge install -u    Uninstall${_C_RST}\n"

  # Hint about PATH if ~/.claude/bin isn't on it
  if [[ ":$PATH:" != *":$HOME/.claude/bin:"* ]]; then
    printf "\n${_C_YELLOW}!${_C_RST} Add ${_C_BOLD}~/.claude/bin${_C_RST} to your PATH to use ${_C_BOLD}forge${_C_RST} from anywhere:\n"
    printf "  ${_C_DIM}echo 'export PATH=\"\$HOME/.claude/bin:\$PATH\"' >> ~/.%s${_C_RST}\n" \
      "$( [[ "$SHELL" == */zsh ]] && echo "zshrc" || echo "bashrc" )"
  fi

  # Hint about shell completions
  if [ -d "$CLAUDE_DIR/completions" ]; then
    local shell_rc
    if [[ "$SHELL" == */zsh ]]; then
      shell_rc=".zshrc"
      printf "\n${_C_DIM}Tab completions: source ~/.claude/completions/forge.zsh${_C_RST}\n"
    else
      shell_rc=".bashrc"
      printf "\n${_C_DIM}Tab completions: source ~/.claude/completions/forge.bash${_C_RST}\n"
    fi
  fi
}

_install_fail_banner() {
  local count="$1"
  printf "\n${_C_RED}${_C_BOLD}%d check(s) failed.${_C_RST} Review errors above.\n" "$count"
}

# ── Help ──────────────────────────────────────────────────────
_install_show_help() {
  printf "\n${_C_BOLD}forge install${_C_RST} — Install or reinstall forge\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge install                           ${_C_DIM}Interactive wizard${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--profile${_C_RST} <name>          ${_C_DIM}Non-interactive install${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--plugins${_C_RST} <group>         ${_C_DIM}Choose plugin group${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--reconfigure${_C_RST}             ${_C_DIM}Re-run persona wizard${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--uninstall${_C_RST}               ${_C_DIM}Remove forge (restores backups)${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--check${_C_RST}                   ${_C_DIM}Health checks only${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--dry-run${_C_RST}                 ${_C_DIM}Show what would be installed${_C_RST}\n"
  printf "  forge install ${_C_BOLD}--quiet${_C_RST}                   ${_C_DIM}Minimal output (CI-friendly)${_C_RST}\n"
  printf "\n${_C_BOLD}Profiles:${_C_RST}\n"
  printf "  ${_C_DIM}product-manager, executive, designer, analyst, data-scientist,${_C_RST}\n"
  printf "  ${_C_DIM}data-engineer, junior-dev, senior-engineer, cto-architect,${_C_RST}\n"
  printf "  ${_C_DIM}devops-engineer, vibe-coder, hobbyist${_C_RST}\n"
  printf "\n${_C_BOLD}Plugin groups:${_C_RST}\n"
  printf "  ${_C_BOLD}full${_C_RST}       All 18 plugins ${_C_DIM}(default for engineering personas)${_C_RST}\n"
  printf "  ${_C_BOLD}standard${_C_RST}   16 plugins ${_C_DIM}(drops HR/legal and startup)${_C_RST}\n"
  printf "  ${_C_BOLD}minimal${_C_RST}    6 core plugins ${_C_DIM}(default for vibe-coder, hobbyist)${_C_RST}\n"
}
