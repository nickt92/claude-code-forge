#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-install — install forge to ~/.claude/
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Extracted from install.sh. Handles onboarding wizard, assembly,
# file copying, settings merge, and plugin installation.
#
# Usage (via forge CLI):
#   forge install
#   forge install --profile senior-engineer
#   forge install --plugins minimal
#   forge install --quiet --profile senior-engineer
#   forge install --reconfigure
#   forge install --uninstall
#   forge install --check

# Dependencies (sourced on demand)
_cmd_install_load_deps() {
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/settings-merge.sh"
  source "$FORGE_SOURCE_DIR/lib/settings-unmerge.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  source "$FORGE_SOURCE_DIR/lib/plugins.sh"
  source "$FORGE_SOURCE_DIR/lib/uninstall.sh"
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

# ── Health Check Function ─────────────────────────────────────
_install_run_health_checks() {
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

  # Rules files (discovered from source)
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    if [ -f "$CLAUDE_DIR/rules/${rule}.md" ]; then
      ((health_pass++))
    else
      fail "rules/${rule}.md missing"; ((health_fail++)); ((errors++))
    fi
  done < <(forge_shipped_rules)

  # Hooks (discovered from source)
  while IFS= read -r hook; do
    [ -n "$hook" ] || continue
    if [ -f "$CLAUDE_DIR/hooks/${hook}.sh" ] && [ -x "$CLAUDE_DIR/hooks/${hook}.sh" ]; then
      ((health_pass++))
    else
      fail "hooks/${hook}.sh missing or not executable"; ((health_fail++)); ((errors++))
    fi
  done < <(forge_shipped_hooks)

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
    if [ "$plugin_count" -ge 5 ]; then
      ((health_pass++))
    elif [ "$plugin_count" -gt 0 ]; then
      warn "Only $plugin_count plugins enabled"; ((health_fail++))
    else
      fail "No plugins enabled in settings.json"; ((health_fail++)); ((errors++))
    fi
  else
    fail "settings.json missing"; ((health_fail++)); ((errors++))
  fi

  debug "health checks complete (pass=$health_pass fail=$health_fail)"

  # Assembly smoke test
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

  local total_pass=$(( health_pass + assembly_pass ))

  if [ "$errors" -eq 0 ] && [ "$health_fail" -eq 0 ] && [ "$assembly_fail" -eq 0 ]; then
    ok "All checks passed (${health_pass} health, ${assembly_pass} assemblies)"
  else
    if [ "$health_fail" -gt 0 ] || [ "$assembly_fail" -gt 0 ]; then
      local total_checks=$(( health_pass + health_fail + assembly_pass + assembly_fail ))
      ok "${total_pass}/${total_checks} checks passed"
    fi
  fi

  return "$errors"
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

# ── Main install command ──────────────────────────────────────
cmd_install() {
  _cmd_install_load_deps

  # Parse arguments
  local PROFILE_ARG=""
  local PLUGINS_ARG=""
  local RECONFIGURE=false
  local RUN_CHECK_ONLY=false
  local DRY_RUN=false
  local SELECTED_PERSONA=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        _install_show_help
        return 0
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
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --uninstall)
        # Require jq for manifest-based uninstall
        if ! command -v jq >/dev/null 2>&1; then
          fail "jq is required for uninstall. Install: brew install jq (macOS) or apt install jq (Linux)"
          return 1
        fi

        banner "Claude Code Forge — Uninstall"
        echo ""
        show_uninstall_preview
        read -p "Continue? (y/N) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 0

        # Read plugin group before uninstall destroys the manifest
        local plugin_group_for_uninstall
        plugin_group_for_uninstall=$(jq -r '.plugin_group // "full"' "$MANIFEST_FILE" 2>/dev/null || echo "full")

        uninstall_forge

        # Offer plugin uninstall
        echo ""
        read -p "Also uninstall forge plugins? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] && command -v claude >/dev/null 2>&1; then
          local plugin_list
          plugin_list=$(resolve_plugin_list "$plugin_group_for_uninstall")
          while IFS= read -r plugin; do
            [ -n "$plugin" ] || continue
            claude plugins remove "$plugin" </dev/null 2>/dev/null || true
          done <<< "$plugin_list"
          ok "Plugins removed"
        fi

        # Remove forge symlink
        rm -f "$CLAUDE_DIR/bin/forge"
        return 0
        ;;
      --profile)
        if [[ $# -lt 2 ]]; then
          fail "Missing profile name after --profile"
          echo "Usage: forge install --profile <name>"
          return 1
        fi
        PROFILE_ARG="$2"
        shift 2
        ;;
      --plugins)
        if [[ $# -lt 2 ]]; then
          fail "Missing group name after --plugins"
          echo "Available groups: $(get_plugin_group_names | tr '\n' ' ')"
          return 1
        fi
        PLUGINS_ARG="$2"
        shift 2
        ;;
      --reconfigure)
        RECONFIGURE=true
        shift
        ;;
      *)
        fail "Unknown option: $1"
        echo "Usage: forge install [--profile <name>] [--plugins <group>] [--reconfigure] [--uninstall] [--quiet] [--help]"
        return 1
        ;;
    esac
  done

  # ── Check-only mode ──
  if [ "$RUN_CHECK_ONLY" = true ]; then
    banner "Claude Code Forge — Health Check"
    if [ -f "$CLAUDE_DIR/profile.json" ]; then
      info "Profile: $(jq -r '.label' "$CLAUDE_DIR/profile.json" 2>/dev/null)"
    fi
    _install_run_health_checks
    return $?
  fi

  # ── Persona selection ──
  if [ -z "$PROFILE_ARG" ] && [ "$RECONFIGURE" = false ]; then
    if [ -f "$CLAUDE_DIR/profile.json" ] && [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
      local existing_persona
      existing_persona=$(jq -r '.persona' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "")
      if [ -n "$existing_persona" ]; then
        banner "Claude Code Forge — Installer"
        echo ""
        local existing_label
        existing_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json" 2>/dev/null || echo "$existing_persona")
        info "Existing profile detected: ${existing_label}"
        echo ""
        echo "  1. Keep current profile and update forge files"
        echo "  2. Choose a new profile"
        echo "  3. Cancel"
        echo ""
        read -p "Your choice [1-3]: " update_choice
        case "$update_choice" in
          1) SELECTED_PERSONA="$existing_persona" ;;
          2) _install_run_wizard ;;
          *) echo "Cancelled."; return 0 ;;
        esac
      else
        _install_run_wizard
      fi
    else
      _install_run_wizard
    fi
  elif [ -n "$PROFILE_ARG" ]; then
    # Check source profiles, then user-space profiles
    if [ ! -f "$PROFILES_DIR/${PROFILE_ARG}.json" ] && [ ! -f "$CLAUDE_DIR/profiles/${PROFILE_ARG}.json" ]; then
      fail "Unknown profile: ${PROFILE_ARG}"
      echo ""
      echo "Available profiles:"
      for key in "${PERSONA_KEYS[@]}"; do
        echo "  - $key"
      done
      # Also list custom profiles from source and user space
      for f in "$PROFILES_DIR"/custom-*.json; do
        [ -f "$f" ] || continue
        echo "  - $(jq -r '.persona' "$f")"
      done
      if [ -d "$CLAUDE_DIR/profiles" ]; then
        for f in "$CLAUDE_DIR/profiles"/custom-*.json; do
          [ -f "$f" ] || continue
          echo "  - $(jq -r '.persona' "$f")"
        done
      fi
      return 1
    fi
    SELECTED_PERSONA="$PROFILE_ARG"
    local local_label
    local_label=$(jq -r '.label' "$PROFILES_DIR/${SELECTED_PERSONA}.json")
    banner "Claude Code Forge — Installer"
    info "Profile: ${local_label}"
  else
    _install_run_wizard
  fi

  local PROFILE_FILE="$PROFILES_DIR/${SELECTED_PERSONA}.json"
  # Fall back to user-space profiles for custom personas
  if [ ! -f "$PROFILE_FILE" ] && [ -f "$CLAUDE_DIR/profiles/${SELECTED_PERSONA}.json" ]; then
    PROFILE_FILE="$CLAUDE_DIR/profiles/${SELECTED_PERSONA}.json"
  fi

  # Resolve plugin group: CLI flag > profile default > "full"
  local PLUGIN_GROUP="$PLUGINS_ARG"
  if [ -z "$PLUGIN_GROUP" ]; then
    PLUGIN_GROUP=$(get_default_plugin_group "$PROFILE_FILE")
  fi

  # ── Dry-run mode ──
  if [ "$DRY_RUN" = true ]; then
    banner "Claude Code Forge — Dry Run"
    local persona_label
    persona_label=$(jq -r '.label' "$PROFILE_FILE")
    kv "Profile" "$persona_label ($SELECTED_PERSONA)"
    kv "Plugins" "$PLUGIN_GROUP"
    kv "Source" "$FORGE_SOURCE_DIR"
    kv "Target" "$CLAUDE_DIR"

    echo ""
    step "Files that would be installed"

    info "CLAUDE.md (assembled from profile)"
    info "profile.json"
    info "statusline-command.sh"
    info "lib/ui.sh"
    info "bin/forge -> $FORGE_SOURCE_DIR/forge"

    local rule_count=0
    for f in "$FORGE_SOURCE_DIR/templates/rules/"*.md; do
      [ -f "$f" ] || continue
      info "rules/$(basename "$f")"
      ((rule_count++))
    done

    local hook_count=0
    for f in "$FORGE_SOURCE_DIR/hooks/"*.sh; do
      [ -f "$f" ] || continue
      info "hooks/$(basename "$f")"
      ((hook_count++))
    done

    local script_count=0
    for f in "$FORGE_SOURCE_DIR/scripts/"*.sh; do
      [ -f "$f" ] || continue
      info "scripts/$(basename "$f")"
      ((script_count++))
    done

    if [ -d "$FORGE_SOURCE_DIR/completions" ]; then
      for f in "$FORGE_SOURCE_DIR/completions/"*; do
        [ -f "$f" ] && info "completions/$(basename "$f")"
      done
    fi

    echo ""
    step "Summary"
    kv "Rules" "$rule_count"
    kv "Hooks" "$hook_count"
    kv "Scripts" "$script_count"

    local plugin_count
    plugin_count=$(resolve_plugin_list "$PLUGIN_GROUP" | grep -c . || echo 0)
    kv "Plugins" "$plugin_count ($PLUGIN_GROUP group)"

    echo ""
    info "No files were modified (dry run)"
    return 0
  fi

  # ── Prerequisites ──
  step "Checking prerequisites"

  local prereq_ok=true
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
    return 1
  fi
  ok "All prerequisites met (claude, jq, $(detect_platform))"

  # ── Backup existing files ──
  step "Backing up configuration"

  mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks"

  # Migrate legacy .backup-* files if present
  if has_legacy_backups; then
    migrate_legacy_backups
  fi

  # Migrate v1 manifest to v2
  manifest_migrate_v1_to_v2

  # Snapshot pre-existing state (no-op on re-install)
  snapshot_pre_install_state
  ok "Backup complete (forge-backup/manifest.json)"

  # ── Assemble and install CLAUDE.md ──
  step "Assembling CLAUDE.md"

  assemble_claude_md "$PROFILE_FILE" "$CLAUDE_DIR/CLAUDE.md"

  local lines
  lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
  if [ "$lines" -le 200 ]; then
    ok "CLAUDE.md assembled ($lines lines)"
  else
    warn "CLAUDE.md is $lines lines (target: under 200) — consider trimming sections"
  fi

  # Save profile.json for future reference
  cp "$PROFILE_FILE" "$CLAUDE_DIR/profile.json"

  # ── Install forge files ──
  step "Installing forge files"

  local rule_count=0
  for rule_file in "$FORGE_SOURCE_DIR/templates/rules/"*.md; do
    cp "$rule_file" "$CLAUDE_DIR/rules/$(basename "$rule_file")"
    ((rule_count++))
  done

  local hook_count=0
  for hook_file in "$FORGE_SOURCE_DIR/hooks/"*.sh; do
    cp "$hook_file" "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    chmod +x "$CLAUDE_DIR/hooks/$(basename "$hook_file")"
    ((hook_count++))
  done

  local script_count=0
  mkdir -p "$CLAUDE_DIR/scripts"
  for script_file in "$FORGE_SOURCE_DIR/scripts/"*.sh; do
    if [ -f "$script_file" ]; then
      cp "$script_file" "$CLAUDE_DIR/scripts/$(basename "$script_file")"
      chmod +x "$CLAUDE_DIR/scripts/$(basename "$script_file")"
      ((script_count++))
    fi
  done

  cp "$FORGE_SOURCE_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"

  # Install ui.sh to ~/.claude/lib/
  mkdir -p "$CLAUDE_DIR/lib"
  cp "$FORGE_SOURCE_DIR/lib/ui.sh" "$CLAUDE_DIR/lib/ui.sh"

  # Install forge CLI to ~/.claude/bin/
  mkdir -p "$CLAUDE_DIR/bin"
  if is_windows 2>/dev/null; then
    # Windows: copy instead of symlink (symlinks require admin/dev mode)
    cp "$FORGE_SOURCE_DIR/forge" "$CLAUDE_DIR/bin/forge"
    # Create .cmd wrapper for cmd.exe / PowerShell
    printf '@bash "%%~dp0forge" %%*\r\n' > "$CLAUDE_DIR/bin/forge.cmd"
  else
    ln -sf "$FORGE_SOURCE_DIR/forge" "$CLAUDE_DIR/bin/forge"
  fi

  # Install shell completions
  mkdir -p "$CLAUDE_DIR/completions"
  if [ -d "$FORGE_SOURCE_DIR/completions" ]; then
    for comp_file in "$FORGE_SOURCE_DIR/completions/"*; do
      [ -f "$comp_file" ] && cp "$comp_file" "$CLAUDE_DIR/completions/$(basename "$comp_file")"
    done
  fi

  # Create user profiles directory
  mkdir -p "$CLAUDE_DIR/profiles"

  ok "${rule_count} rules, ${hook_count} hooks, ${script_count} scripts, statusline installed"

  # ── Merge settings.json ──
  step "Configuring settings"

  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    local EXISTING="$CLAUDE_DIR/settings.json"
    local TEMPLATE="$FORGE_SOURCE_DIR/templates/settings.json"

    # Migration: replace prompt-classifier with session-init
    if jq -e '.hooks.UserPromptSubmit[]? | select(.hooks[]?.command | contains("prompt-classifier"))' "$EXISTING" >/dev/null 2>&1; then
      jq '(.hooks.UserPromptSubmit // []) |= map(select(.hooks[]?.command | contains("prompt-classifier") | not))' "$EXISTING" > "$EXISTING.migrated"
      mv "$EXISTING.migrated" "$EXISTING"
    fi
    rm -f "$CLAUDE_DIR/hooks/prompt-classifier.sh"

    merge_settings "$EXISTING" "$TEMPLATE" "$CLAUDE_DIR/settings.json.tmp"
    mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
    ok "Settings merged (preserved existing config)"
  else
    cp "$FORGE_SOURCE_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
    ok "Settings installed (fresh)"
  fi

  # ── Update manifest with installed files ──
  update_manifest_installed "$(jq -r '.persona' "$PROFILE_FILE")" "$FORGE_SOURCE_DIR" "$PLUGIN_GROUP"

  # ── Install plugins ──
  step "Installing plugins"

  local plugin_list
  plugin_list=$(resolve_plugin_list "$PLUGIN_GROUP")
  install_plugins "$plugin_list"

  # ── Verify installation ──
  _install_run_health_checks
  local check_errors=$?

  # ── Summary ──
  if [ "$check_errors" -eq 0 ]; then
    local persona_label md_lines
    persona_label=$(jq -r '.label' "$CLAUDE_DIR/profile.json")
    md_lines=$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ')
    _install_success_banner "$persona_label" "$md_lines"
  else
    _install_fail_banner "$check_errors"
    return 1
  fi
}
