#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-install — install forge to ~/.claude/
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Orchestrates onboarding wizard, assembly, file copying,
# settings merge, and plugin installation.
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
  source "$FORGE_SOURCE_DIR/lib/install-wizard.sh"
  source "$FORGE_SOURCE_DIR/lib/install-checks.sh"
}

# ── Project defaults ──────────────────────────────────────────
# Reads .forge/defaults.json from the current directory if present.
# Returns defaults via global variables: _DEFAULT_PERSONA, _DEFAULT_PLUGINS,
# _DEFAULT_PERMISSIONS, _DEFAULT_PLANNING_ENFORCEMENT.
# Missing file or malformed JSON = no-op.
_read_project_defaults() {
  _DEFAULT_PERSONA=""
  _DEFAULT_PLUGINS=""
  _DEFAULT_PERMISSIONS=""
  _DEFAULT_PLANNING_ENFORCEMENT=""

  local defaults_file
  defaults_file="$(pwd)/.forge/defaults.json"
  [ -f "$defaults_file" ] || return 0

  # Validate JSON before reading
  jq empty "$defaults_file" 2>/dev/null || return 0

  _DEFAULT_PERSONA=$(jq -r '.persona // empty' "$defaults_file" 2>/dev/null)
  _DEFAULT_PLUGINS=$(jq -r '.plugins // empty' "$defaults_file" 2>/dev/null)
  _DEFAULT_PERMISSIONS=$(jq -r '.permissions // empty' "$defaults_file" 2>/dev/null)
  _DEFAULT_PLANNING_ENFORCEMENT=$(jq -r '.planning_enforcement // empty' "$defaults_file" 2>/dev/null)
}

# ── Main install command ──────────────────────────────────────
cmd_install() {
  _cmd_install_load_deps

  # Read project defaults early (before argument parsing)
  _read_project_defaults

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
  # Apply project default persona when no CLI flag provided
  if [ -z "$PROFILE_ARG" ] && [ -n "$_DEFAULT_PERSONA" ]; then
    PROFILE_ARG="$_DEFAULT_PERSONA"
  fi

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

  # Resolve plugin group: CLI flag > project default > profile default > "full"
  local PLUGIN_GROUP="$PLUGINS_ARG"
  if [ -z "$PLUGIN_GROUP" ] && [ -n "$_DEFAULT_PLUGINS" ]; then
    PLUGIN_GROUP="$_DEFAULT_PLUGINS"
  fi
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
