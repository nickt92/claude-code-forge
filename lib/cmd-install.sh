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

# ── Orphaned hook scripts ─────────────────────────────────────
# Delete the script files for hooks forge previously installed and no longer
# ships, so ~/.claude/hooks/ does not accumulate dead files. Only names the
# manifest records as forge-installed are considered, so a script the user
# wrote into that directory is never removed.
#
# Args: $1 — JSON array of previously-installed basenames
#       $2 — JSON array of currently-shipped basenames
_install_delete_orphan_scripts() {
  local previously_owned="$1"
  local currently_shipped="$2"
  local orphan

  while IFS= read -r orphan; do
    [ -n "$orphan" ] || continue
    # Guard against a manifest entry that is not a plain script name.
    case "$orphan" in
      */*|.*|"") continue ;;
    esac
    local target="$CLAUDE_DIR/hooks/${orphan}.sh"
    [ -f "$target" ] && rm -- "$target"
  done < <(jq -r -n --argjson o "$previously_owned" --argjson s "$currently_shipped" \
             '($o - $s)[]' 2>/dev/null || true)
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
  local PERMISSIONS_ARG=""
  local RECONFIGURE=false
  local RUN_CHECK_ONLY=false
  local DRY_RUN=false
  local SELECTED_PERSONA=""
  local SELECTED_PERMISSIONS=""

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
          forge_fail "jq is required for uninstall. Install: brew install jq (macOS) or apt install jq (Linux)"
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
            claude plugin uninstall "$plugin" --scope user </dev/null 2>/dev/null || true
          done <<< "$plugin_list"
          ok "Plugins removed"
        fi

        # Remove forge symlink
        rm -f "$CLAUDE_DIR/bin/forge"
        return 0
        ;;
      --profile)
        if [[ $# -lt 2 ]]; then
          forge_fail "Missing profile name after --profile"
          echo "Usage: forge install --profile <name>"
          return 1
        fi
        PROFILE_ARG="$2"
        shift 2
        ;;
      --plugins)
        if [[ $# -lt 2 ]]; then
          forge_fail "Missing group name after --plugins"
          echo "Available groups: $(get_plugin_group_names | tr '\n' ' ')"
          return 1
        fi
        PLUGINS_ARG="$2"
        shift 2
        ;;
      --permissions)
        if [[ $# -lt 2 ]]; then
          forge_fail "Missing preset name after --permissions"
          echo "Available presets: ask-before-changes, auto-edit, full-autonomy"
          return 1
        fi
        PERMISSIONS_ARG="$2"
        shift 2
        ;;
      --reconfigure)
        RECONFIGURE=true
        shift
        ;;
      *)
        forge_fail "Unknown option: $1"
        echo "Usage: forge install [--profile <name>] [--plugins <group>] [--permissions <preset>] [--reconfigure] [--uninstall] [--quiet] [--help]"
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
      forge_fail "Unknown profile: ${PROFILE_ARG}"
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

  # Resolve permissions: CLI flag > project default > wizard selection
  if [ -n "$PERMISSIONS_ARG" ]; then
    SELECTED_PERMISSIONS="$PERMISSIONS_ARG"
  elif [ -z "$SELECTED_PERMISSIONS" ] && [ -n "$_DEFAULT_PERMISSIONS" ]; then
    SELECTED_PERMISSIONS="$_DEFAULT_PERMISSIONS"
  fi

  # ── Dry-run mode ──
  if [ "$DRY_RUN" = true ]; then
    banner "Claude Code Forge — Dry Run"
    local persona_label
    persona_label=$(jq -r '.label' "$PROFILE_FILE")
    kv "Profile" "$persona_label ($SELECTED_PERSONA)"
    kv "Plugins" "$PLUGIN_GROUP"
    kv "Permissions" "${SELECTED_PERMISSIONS:-none}"
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
    plugin_count=$(resolve_plugin_list "$PLUGIN_GROUP" | grep -c . || true)
    kv "Plugins" "$plugin_count ($PLUGIN_GROUP group)"

    echo ""
    info "No files were modified (dry run)"
    return 0
  fi

  # ── Prerequisites ──
  step "Checking prerequisites"

  local prereq_ok=true

  # Verify Claude Code can support what we are about to write, BEFORE anything
  # is backed up or modified — a failure here must cost the user nothing. This
  # replaces a bare `command -v claude`, which was true the whole time
  # `claude plugins add` was silently failing to install a single plugin.
  source "$FORGE_SOURCE_DIR/lib/cc-compat.sh"
  if ! cc_compat_check "${UI_QUIET:-false}"; then
    prereq_ok=false
  fi

  if ! command -v jq >/dev/null 2>&1; then
    forge_fail "jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
    prereq_ok=false
  fi
  if ! check_platform 2>/dev/null; then
    forge_fail "Unsupported platform"
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
  manifest_migrate_v2_to_v3

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

    # Undo point before we rewrite the user's settings.
    snapshot_settings_history "install"

    # Remove hook registrations forge installed previously but no longer ships.
    # This replaces a hardcoded prompt-classifier special case that only ever
    # covered one hook — plan-checkpoint, dropped in 1.3.0, was missed and is
    # still registered on installed machines. Driven by the manifest, so a
    # script the user placed in ~/.claude/hooks/ themselves is never touched.
    local _previously_owned _currently_shipped
    _previously_owned=$(jq -c '[.installed.directories.hooks[]? | sub("\\.sh$"; "")]' \
      "$MANIFEST_FILE" 2>/dev/null || echo '[]')
    [ -n "$_previously_owned" ] || _previously_owned='[]'
    _currently_shipped=$(forge_shipped_hooks | jq -R . | jq -s -c .)
    purge_orphaned_hooks "$EXISTING" "$_previously_owned" "$_currently_shipped"
    _install_delete_orphan_scripts "$_previously_owned" "$_currently_shipped"

    merge_settings "$EXISTING" "$TEMPLATE" "$CLAUDE_DIR/settings.json.tmp"
    mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
    ok "Settings merged (preserved existing config)"
  else
    cp "$FORGE_SOURCE_DIR/templates/settings.json" "$CLAUDE_DIR/settings.json"
    ok "Settings installed (fresh)"
  fi

  # ── Apply permission preset ──
  if [ -n "$SELECTED_PERMISSIONS" ]; then
    source "$FORGE_SOURCE_DIR/lib/permissions-merge.sh"
    local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"

    # Validate preset name
    local valid
    valid=$(jq -r --arg name "$SELECTED_PERMISSIONS" '.presets[$name] // empty' "$PRESETS_FILE")
    if [ -z "$valid" ]; then
      warn "Unknown permissions preset: $SELECTED_PERMISSIONS — skipping"
    else
      # Undo point before the permission arrays are rewritten. install rewrites
      # them inline rather than going through _permissions_apply, so it needs its
      # own snapshot.
      snapshot_settings_history "install-permissions"

      # Remove only what forge previously added — never rules the user had
      # first. Manifests written before 2.0 store owned as a bare allow array;
      # unmerge_permissions accepts either shape.
      # A bare array is what a pre-2.0 manifest would hold, and it is an allow
      # list. Mapping it to an empty allow would make install skip the unmerge,
      # leave the 1.x wildcards in place, and then re-classify them as adopted —
      # permanently unremovable. uninstall.sh reads it the same way.
      if [ -f "$MANIFEST_FILE" ]; then
        local old_owned
        old_owned=$(jq -c '
          (.installed.permissions.owned // {}) as $o |
          if ($o | type) == "object"
          then { allow: ($o.allow // []), ask: ($o.ask // []), deny: ($o.deny // []) }
          elif ($o | type) == "array" then { allow: $o, ask: [], deny: [] }
          else { allow: [], ask: [], deny: [] } end
        ' "$MANIFEST_FILE" 2>/dev/null) || old_owned=""
        [ -n "$old_owned" ] || old_owned='{"allow":[],"ask":[],"deny":[]}'
        if [ "$(echo "$old_owned" | jq '[.allow,.ask,.deny]|add|length')" -gt 0 ]; then
          unmerge_permissions "$CLAUDE_DIR/settings.json" "$old_owned"
        fi
      fi

      # deny is opt-in via `forge permissions --with-deny`; install never
      # writes it. A permission rule has no override, so the first time a user
      # meets one it should be because they asked for it.
      #
      # Exceptions must be subtracted here, not left to merge_permissions —
      # that re-resolves from the presets file and would silently reinstate a
      # security rule the user explicitly opted out of.
      local perm_allow perm_ask perm_exceptions='[]'
      if [ -f "$MANIFEST_FILE" ]; then
        perm_exceptions=$(jq -c '.installed.permissions.exceptions // []' \
          "$MANIFEST_FILE" 2>/dev/null) || perm_exceptions='[]'
        [ -n "$perm_exceptions" ] || perm_exceptions='[]'
      fi
      perm_allow=$(resolve_preset_rules "$SELECTED_PERMISSIONS" "$PRESETS_FILE" allow \
        | jq -c --argjson ex "$perm_exceptions" '. - $ex')
      perm_ask=$(resolve_preset_rules "$SELECTED_PERMISSIONS" "$PRESETS_FILE" ask \
        | jq -c --argjson ex "$perm_exceptions" '. - $ex')

      # A user who opted into deny with `forge permissions --with-deny` keeps
      # it across reinstalls and `forge update`.
      local perm_deny='[]'
      if [ -f "$MANIFEST_FILE" ] \
         && jq -e '.installed.permissions.with_deny == true' "$MANIFEST_FILE" >/dev/null 2>&1; then
        perm_deny=$(resolve_preset_rules "$SELECTED_PERMISSIONS" "$PRESETS_FILE" deny \
          | jq -c --argjson ex "$perm_exceptions" '. - $ex')
      fi

      # Computed after the unmerge, before the merge — see _permissions_apply.
      _INSTALL_PERM_OWNERSHIP=$(compute_permission_ownership \
        "$CLAUDE_DIR/settings.json" "$perm_allow" "$perm_ask" '[]')

      merge_permission_rules "$CLAUDE_DIR/settings.json" "$perm_allow" "$perm_ask" '[]'

      # Same ownership guard as `forge permissions --preset`: forge writes the
      # mode only when the key is unset or still holds what forge last wrote.
      local desired_mode prev_mode=""
      desired_mode=$(resolve_preset_default_mode "$SELECTED_PERMISSIONS" "$PRESETS_FILE")
      if [ -f "$MANIFEST_FILE" ]; then
        prev_mode=$(jq -r '.installed.permissions.default_mode.written // empty' \
          "$MANIFEST_FILE" 2>/dev/null) || prev_mode=""
      fi
      # Captured before the write so pre_existing records what was really there.
      _INSTALL_PERM_MODE_PRE=$(jq -r '.permissions.defaultMode // empty' \
        "$CLAUDE_DIR/settings.json" 2>/dev/null) || _INSTALL_PERM_MODE_PRE=""

      # rc 1 and rc 2 are both normal outcomes. install runs under `set -e`, so
      # a bare call would abort here — after settings.json was rewritten and
      # before the manifest recorded ownership of any of it.
      local mode_rc=0
      merge_default_mode "$CLAUDE_DIR/settings.json" "$desired_mode" "$prev_mode" \
        || mode_rc=$?
      case "$mode_rc" in
        0) _INSTALL_PERM_MODE="$desired_mode" ;;
        1) warn "Left permissions.defaultMode as you set it"; _INSTALL_PERM_MODE="" ;;
        *) _INSTALL_PERM_MODE="" ;;
      esac

      ok "Permissions: $(jq -r --arg id "$SELECTED_PERMISSIONS" '.presets[$id].label' "$PRESETS_FILE") ($(echo "$perm_allow" | jq 'length') auto-approved, $(echo "$perm_ask" | jq 'length') always ask)"
    fi
  fi

  # ── Update manifest with installed files ──
  update_manifest_installed "$(jq -r '.persona' "$PROFILE_FILE")" "$FORGE_SOURCE_DIR" "$PLUGIN_GROUP"

  # Record which permission rules forge owns, from the split computed before
  # the merge. update_manifest_installed carries .installed.permissions across,
  # so this only needs to write it when a preset was applied.
  if [ -n "$SELECTED_PERMISSIONS" ] && [ -f "$MANIFEST_FILE" ] && [ -n "${_INSTALL_PERM_OWNERSHIP:-}" ]; then
    local presets_version
    presets_version=$(jq -r '.presets_version // "unknown"' \
      "$FORGE_SOURCE_DIR/templates/permission-presets.json" 2>/dev/null)
    jq --arg preset "$SELECTED_PERMISSIONS" \
       --arg pv "$presets_version" \
       --arg mode "${_INSTALL_PERM_MODE:-}" \
       --arg mode_pre "${_INSTALL_PERM_MODE_PRE:-}" \
       --argjson own "$_INSTALL_PERM_OWNERSHIP" '
      .installed.permissions = {
        schema: 2,
        preset: $preset,
        presets_version: $pv,
        provenance: (.installed.permissions.provenance // "native"),
        with_deny: (.installed.permissions.with_deny // false),
        owned: $own.owned,
        adopted: $own.adopted,
        exceptions: (.installed.permissions.exceptions // []),
        default_mode: {
          written: (if $mode == "" then null else $mode end),
          pre_existing: (
            if (.installed.permissions.default_mode.pre_existing) != null
            then .installed.permissions.default_mode.pre_existing
            elif $mode_pre == "" then null
            else $mode_pre end)
        }
      }
    ' "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp"
    mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
  fi

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
