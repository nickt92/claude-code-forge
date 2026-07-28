#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-permissions — manage Claude Code permission presets
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Apply curated permission presets to ~/.claude/settings.json
# that control what Claude Code can do without asking.
#
# Usage:
#   forge permissions                      Show current preset + effective rules
#   forge permissions --list               List available presets
#   forge permissions --preset <name>      Apply a preset
#   forge permissions --explain '<cmd>'    Show which rule decides a command
#   forge permissions --except <rule>      Record a rule forge must not apply
#   forge permissions --diff               Preview changes without writing
#   forge permissions --with-deny          Also write the deny list (opt-in)
#   forge permissions --json               Machine-readable output

cmd_permissions() {
  source "$FORGE_SOURCE_DIR/lib/permissions-merge.sh"
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  # Bring the manifest up to the current schema before anything reads
  # .installed. Without this, a 1.x manifest has no .installed.permissions.owned,
  # so the unmerge finds nothing to remove and every rule this release exists to
  # withdraw — Bash(bash:*), Bash(xargs:*), Bash(aws:*), Bash(gh:*) — survives
  # while the new ask rules are added on top. The user sees new prompts and
  # concludes the migration ran.
  #
  # It also has to happen here rather than only in cmd_install, or the two write
  # .installed.permissions from different sources with no ordering guarantee.
  if [ -f "$MANIFEST_FILE" ]; then
    manifest_migrate_v1_to_v2
    manifest_migrate_v2_to_v3
  fi

  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  local json_mode=false
  local list_mode=false
  local diff_mode=false
  local with_deny=false
  local assume_yes=false
  local preset_name=""
  local explain_cmd=""
  local except_rule=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)      json_mode=true; shift ;;
      --list)      list_mode=true; shift ;;
      --diff)      diff_mode=true; shift ;;
      --with-deny) with_deny=true; shift ;;
      --yes|-y)    assume_yes=true; shift ;;
      --preset)
        shift
        preset_name="${1:-}"
        [ -z "$preset_name" ] && { forge_fail "Missing preset name after --preset"; return 1; }
        shift
        ;;
      --explain)
        shift
        explain_cmd="${1:-}"
        [ -z "$explain_cmd" ] && { forge_fail "Missing command after --explain"; return 1; }
        shift
        ;;
      --except)
        shift
        except_rule="${1:-}"
        [ -z "$except_rule" ] && { forge_fail "Missing rule after --except"; return 1; }
        shift
        ;;
      --help|-h) _permissions_help; return 0 ;;
      *) shift ;;
    esac
  done

  if [ -n "$explain_cmd" ]; then
    _permissions_explain "$explain_cmd"
  elif [ -n "$except_rule" ]; then
    _permissions_except "$except_rule"
  elif [ -n "$preset_name" ]; then
    _permissions_apply "$preset_name"
  elif $list_mode; then
    _permissions_list
  else
    _permissions_show
  fi
}

# ── List presets ─────────────────────────────────────────────

_permissions_list() {
  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"

  if $json_mode; then
    # `permissions` is retained alongside `allow` because the desktop app
    # decodes it. The whole contract moves to snake_case in one sweep rather
    # than drifting key by key.
    jq '
      [.presets | to_entries[] | {
        id: .key,
        label: .value.label,
        tier: .value.tier,
        description: .value.description,
        detail: .value.detail,
        permissions: .value.allow,
        allow: .value.allow,
        defaultMode: .value.default_mode,
        inherits: .value.inherits
      }] | sort_by(.tier)
    ' "$PRESETS_FILE"
  else
    printf "\n${_C_BOLD}forge permissions${_C_RST} — Claude Code permission presets\n"
    printf "\n${_C_BOLD}Available presets:${_C_RST}\n\n"

    local ids
    ids=$(jq -r '.presets | to_entries | sort_by(.value.tier)[] | .key' "$PRESETS_FILE")

    while IFS= read -r id; do
      local label tier desc detail recommended=""
      label=$(jq -r --arg id "$id" '.presets[$id].label' "$PRESETS_FILE")
      tier=$(jq -r --arg id "$id" '.presets[$id].tier' "$PRESETS_FILE")
      desc=$(jq -r --arg id "$id" '.presets[$id].description' "$PRESETS_FILE")
      detail=$(jq -r --arg id "$id" '.presets[$id].detail' "$PRESETS_FILE")

      [ "$id" = "full-autonomy" ] && recommended=" ${_C_GREEN}(recommended)${_C_RST}"

      printf "  ${_C_BOLD}%s${_C_RST}%s\n" "$label" "$recommended"
      printf "  ${_C_DIM}Tier %s — %s${_C_RST}\n" "$tier" "$id"
      printf "  %s\n" "$desc"
      printf "  ${_C_DIM}%s${_C_RST}\n\n" "$detail"
    done <<< "$ids"

    local ask_n
    ask_n=$(jq '.global.ask | length' "$PRESETS_FILE")
    printf "${_C_DIM}All presets also carry %s tier-independent \"ask\" rules —${_C_RST}\n" "$ask_n"
    printf "${_C_DIM}destructive and credential-touching commands always prompt.${_C_RST}\n\n"
    printf "${_C_DIM}Apply with: forge permissions --preset <name>${_C_RST}\n"
  fi
}

# ── Show current state ───────────────────────────────────────

_permissions_show() {
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  local current_preset="none"
  local current_permissions='[]' current_ask='[]' current_deny='[]'
  local default_mode="unset"

  if [ -f "$MANIFEST_FILE" ]; then
    current_preset=$(jq -r '.installed.permissions.preset // "none"' "$MANIFEST_FILE" 2>/dev/null)
  fi

  # A hand-broken settings.json is the most likely reason someone runs this
  # command at all, so it must not be the one input that makes it crash.
  local settings_ok=true
  if [ -f "$SETTINGS_FILE" ]; then
    if jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
      current_permissions=$(jq -c '.permissions.allow // []' "$SETTINGS_FILE") || current_permissions='[]'
      current_ask=$(jq -c '.permissions.ask // []' "$SETTINGS_FILE") || current_ask='[]'
      current_deny=$(jq -c '.permissions.deny // []' "$SETTINGS_FILE") || current_deny='[]'
      default_mode=$(jq -r '.permissions.defaultMode // "unset"' "$SETTINGS_FILE") || default_mode="unset"
    else
      settings_ok=false
    fi
  fi

  if ! $settings_ok; then
    if $json_mode; then
      jq -n --arg f "$SETTINGS_FILE" \
        '{error: "invalid-settings-json", file: $f}'
    else
      forge_fail "settings.json is not valid JSON: $SETTINGS_FILE"
      printf "${_C_DIM}Restore a working copy with: forge restore --list${_C_RST}\n"
    fi
    return 1
  fi

  if $json_mode; then
    jq -n \
      --arg preset "$current_preset" \
      --arg mode "$default_mode" \
      --argjson permissions "$current_permissions" \
      --argjson ask "$current_ask" \
      --argjson deny "$current_deny" \
      '{currentPreset: $preset, effectivePermissions: $permissions,
        askRules: $ask, denyRules: $deny, defaultMode: $mode}'
  else
    printf "\n${_C_BOLD}Permission Status${_C_RST}\n\n"

    if [ "$current_preset" = "none" ]; then
      printf "  Preset: ${_C_DIM}none (Claude asks for everything)${_C_RST}\n"
    else
      local label
      label=$(jq -r --arg id "$current_preset" '.presets[$id].label // $id' \
        "$FORGE_SOURCE_DIR/templates/permission-presets.json" 2>/dev/null)
      printf "  Preset: ${_C_BOLD}%s${_C_RST} (%s)\n" "$label" "$current_preset"
    fi

    printf "  Auto-approved: ${_C_BOLD}%s${_C_RST}   Always ask: ${_C_BOLD}%s${_C_RST}   Denied: ${_C_BOLD}%s${_C_RST}\n" \
      "$(echo "$current_permissions" | jq 'length')" \
      "$(echo "$current_ask" | jq 'length')" \
      "$(echo "$current_deny" | jq 'length')"

    # The mode decides whether the deny list means anything at all, so it is
    # reported next to the preset rather than buried in settings.json.
    if [ "$default_mode" = "bypassPermissions" ]; then
      printf "  Default mode: ${_C_YELLOW}%s${_C_RST} ${_C_DIM}— deny rules are ignored in this mode; ask rules still prompt${_C_RST}\n" "$default_mode"
    else
      printf "  Default mode: %s\n" "$default_mode"
    fi

    printf "\n${_C_DIM}Why did that prompt?  forge permissions --explain 'git push --force'${_C_RST}\n"
    printf "${_C_DIM}Change preset:        forge permissions --preset <name>${_C_RST}\n"
    printf "${_C_DIM}List presets:         forge permissions --list${_C_RST}\n"
  fi
}

# ── Explain a command ────────────────────────────────────────

_permissions_explain() {
  local command="$1"
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  local result behavior rule
  # A jq failure here used to be swallowed by the substitution, leaving
  # behavior empty and printing "no forge rule matches" — the wrong answer, with
  # no error and a zero exit code.
  if ! result=$(explain_permission "$SETTINGS_FILE" "$command"); then
    forge_fail "Could not evaluate rules in $SETTINGS_FILE"
    return 1
  fi
  behavior=${result%%	*}
  rule=${result#*	}

  if $json_mode; then
    jq -n --arg cmd "$command" --arg behavior "$behavior" --arg rule "$rule" \
      '{command: $cmd, behavior: $behavior, rule: $rule}'
    return 0
  fi

  printf "\n  ${_C_BOLD}%s${_C_RST}\n\n" "$command"
  case "$behavior" in
    deny)  printf "  ${_C_RED}denied${_C_RST} by %s\n" "$rule" ;;
    ask)   printf "  ${_C_YELLOW}asks${_C_RST} because of %s\n" "$rule" ;;
    allow) printf "  ${_C_GREEN}auto-approved${_C_RST} by %s\n" "$rule" ;;
    *)     printf "  ${_C_DIM}no forge rule matches — Claude Code decides${_C_RST}\n" ;;
  esac

  printf "\n  ${_C_DIM}Evaluation order is deny, then ask, then allow. The first match wins.${_C_RST}\n"

  # The honest part. Most unexpected prompts are not missing rules — they are
  # command shapes Claude Code refuses to match a rule against at all, and no
  # preset can change that.
  local note=""
  case "$command" in
    *"&&"*|*";"*|*"|"*) note="compound" ;;
  esac
  case "$command" in
    *'$('*)             note="substitution" ;;
  esac
  case "$command" in
    "cd "*)             note="cd" ;;
  esac

  case "$note" in
    cd)
      printf "\n  ${_C_DIM}Note: a command that changes directory and then runs git always asks,${_C_RST}\n"
      printf "  ${_C_DIM}regardless of your preset — the target directory could carry git hooks.${_C_RST}\n"
      ;;
    compound)
      printf "\n  ${_C_DIM}Note: every part of a compound command must be allowed on its own.${_C_RST}\n"
      printf "  ${_C_DIM}One unmatched part makes the whole command prompt.${_C_RST}\n"
      ;;
    substitution)
      printf "\n  ${_C_DIM}Note: command substitution is analysed conservatively and often prompts${_C_RST}\n"
      printf "  ${_C_DIM}whatever the rules say.${_C_RST}\n"
      ;;
  esac
  printf "\n"
}

# ── Record an exception ──────────────────────────────────────

_permissions_except() {
  local rule="$1"

  if [ ! -f "$MANIFEST_FILE" ]; then
    forge_fail "No manifest found — run 'forge install' first"
    return 1
  fi

  local tmp="${MANIFEST_FILE}.tmp"
  jq --arg rule "$rule" '
    .installed.permissions.exceptions =
      (((.installed.permissions.exceptions // []) + [$rule]) | unique)
  ' "$MANIFEST_FILE" > "$tmp"
  mv "$tmp" "$MANIFEST_FILE"

  ok "forge will no longer apply ${_C_BOLD}${rule}${_C_RST}"
  printf "${_C_DIM}Takes effect on the next 'forge permissions --preset' or 'forge install'.${_C_RST}\n"
}

_permissions_exceptions() {
  [ -f "$MANIFEST_FILE" ] || { echo '[]'; return 0; }
  jq -c '.installed.permissions.exceptions // []' "$MANIFEST_FILE" 2>/dev/null || echo '[]'
}

# ── Apply preset ─────────────────────────────────────────────

_permissions_apply() {
  local preset_name="$1"
  local PRESETS_FILE="$FORGE_SOURCE_DIR/templates/permission-presets.json"
  local SETTINGS_FILE="$CLAUDE_DIR/settings.json"

  # cmd_permissions declares these; callers that reach this function directly
  # (install, tests) get the safe defaults rather than an empty expansion.
  local json_mode="${json_mode:-false}"
  local diff_mode="${diff_mode:-false}"
  local with_deny="${with_deny:-false}"
  local assume_yes="${assume_yes:-false}"

  local valid
  valid=$(jq -r --arg name "$preset_name" '.presets[$name] // empty' "$PRESETS_FILE")
  if [ -z "$valid" ]; then
    forge_fail "Unknown preset: $preset_name"
    printf "\n${_C_DIM}Available presets:${_C_RST}\n"
    jq -r '.presets | keys[]' "$PRESETS_FILE" | while IFS= read -r id; do
      printf "  %s\n" "$id"
    done
    return 1
  fi

  local exceptions
  exceptions=$(_permissions_exceptions)

  # A user who opted into deny keeps it across re-applies. Otherwise the next
  # `forge permissions --preset` removes the rules it owns and says nothing,
  # because removing what forge owns is exactly what it is supposed to do.
  if ! $with_deny && [ -f "$MANIFEST_FILE" ]; then
    if jq -e '.installed.permissions.with_deny == true' "$MANIFEST_FILE" >/dev/null 2>&1; then
      with_deny=true
    fi
  fi

  local allow ask deny
  allow=$(resolve_preset_rules "$preset_name" "$PRESETS_FILE" allow \
    | jq -c --argjson ex "$exceptions" '. - $ex')
  ask=$(resolve_preset_rules "$preset_name" "$PRESETS_FILE" ask \
    | jq -c --argjson ex "$exceptions" '. - $ex')
  if $with_deny; then
    deny=$(resolve_preset_rules "$preset_name" "$PRESETS_FILE" deny \
      | jq -c --argjson ex "$exceptions" '. - $ex')
  else
    deny='[]'
  fi

  # What forge is about to take away, and what stops being auto-approved.
  local old_owned='{"allow":[],"ask":[],"deny":[]}'
  if [ -f "$MANIFEST_FILE" ]; then
    old_owned=$(jq -c '
      (.installed.permissions.owned // {}) as $o |
      if ($o | type) == "object"
      then { allow: ($o.allow // []), ask: ($o.ask // []), deny: ($o.deny // []) }
      else { allow: [], ask: [], deny: [] } end
    ' "$MANIFEST_FILE" 2>/dev/null) || old_owned='{"allow":[],"ask":[],"deny":[]}'
  fi

  local removing newly_prompting
  removing=$(jq -n --argjson old "$old_owned" --argjson new "$allow" \
    '$old.allow - $new')

  # Measured against what the user actually has, not against forge's ownership
  # record: a rule only "stops being auto-approved" if something in the live
  # allow array covers it today. The record is also the wrong source — 1.x
  # expressed these as broad wildcards (Bash(gh:*)), never as the narrow rules
  # they are being replaced by.
  local live_allow='[]'
  if [ -f "$SETTINGS_FILE" ]; then
    live_allow=$(jq -c '.permissions.allow // []' "$SETTINGS_FILE" 2>/dev/null) \
      || live_allow='[]'
    [ -n "$live_allow" ] || live_allow='[]'
  fi
  newly_prompting=$(resolve_newly_prompting "$PRESETS_FILE" "$live_allow")

  if $diff_mode && $json_mode; then
    # The plan requires the desktop app to show the same diff and take the same
    # confirmation. --diff is that mechanism, so it has to be machine-readable
    # when asked for machine-readable output.
    local cur_allow='[]' cur_ask='[]'
    if [ -f "$SETTINGS_FILE" ]; then
      cur_allow=$(jq -c '.permissions.allow // []' "$SETTINGS_FILE" 2>/dev/null) || cur_allow='[]'
      cur_ask=$(jq -c '.permissions.ask // []' "$SETTINGS_FILE" 2>/dev/null) || cur_ask='[]'
    fi
    jq -n --arg preset "$preset_name" \
      --argjson allow "$allow" --argjson ask "$ask" --argjson deny "$deny" \
      --argjson curAllow "$cur_allow" --argjson curAsk "$cur_ask" \
      --argjson removing "$removing" --argjson newly "$newly_prompting" '
      {applied: false, preset: $preset,
       addingAllow: ($allow - $curAllow), addingAsk: ($ask - $curAsk),
       addingDeny: $deny, removing: $removing, newlyPrompting: $newly}'
    return 0
  fi

  if $diff_mode || ! $json_mode; then
    _permissions_print_diff "$SETTINGS_FILE" "$allow" "$ask" "$deny" "$removing" "$newly_prompting"
  fi
  if $diff_mode; then
    printf "\n${_C_DIM}Nothing written. Re-run without --diff to apply.${_C_RST}\n"
    return 0
  fi

  # "Never silently downgrade an effective permission." A count in a summary
  # line is not consent, so the confirmation only appears when something the
  # user currently has auto-approved would start prompting.
  #
  # --json is NOT an escape hatch here. It is the path the desktop app and any
  # scripted caller take, which is exactly where a silent downgrade would go
  # unnoticed; it has to pass --yes like everyone else.
  local downgrades
  downgrades=$(jq -n --argjson a "$removing" --argjson b "$newly_prompting" \
    '($a + $b) | unique | length')
  if [ "$downgrades" -gt 0 ] && ! $assume_yes; then
    if $json_mode; then
      jq -n --argjson removing "$removing" --argjson newly "$newly_prompting" \
        '{applied: false, reason: "downgrade-requires-consent",
          removing: $removing, newlyPrompting: $newly}'
      return 1
    fi
    if [ -t 0 ]; then
      local reply
      read -r -p "  Apply, and start prompting for those ${downgrades} commands? [y/N] " reply
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) printf "  ${_C_DIM}Cancelled — nothing written.${_C_RST}\n"; return 1 ;;
      esac
    else
      forge_fail "Refusing to downgrade ${downgrades} permissions non-interactively — pass --yes"
      return 1
    fi
  fi

  snapshot_settings_history "permissions"

  if [ "$(echo "$old_owned" | jq '[.allow,.ask,.deny]|add|length')" -gt 0 ]; then
    unmerge_permissions "$SETTINGS_FILE" "$old_owned"
  fi

  local ownership
  ownership=$(compute_permission_ownership "$SETTINGS_FILE" "$allow" "$ask" "$deny")

  merge_permission_rules "$SETTINGS_FILE" "$allow" "$ask" "$deny"

  local mode_note=""
  local desired_mode
  desired_mode=$(resolve_preset_default_mode "$preset_name" "$PRESETS_FILE")
  local prev_written=""
  if [ -f "$MANIFEST_FILE" ]; then
    prev_written=$(jq -r '.installed.permissions.default_mode.written // empty' \
      "$MANIFEST_FILE" 2>/dev/null) || prev_written=""
  fi

  # Captured before the write, from settings rather than the manifest — install
  # already did this, and the two writers of the same record must not disagree
  # about where pre_existing comes from.
  local mode_pre=""
  if [ -f "$SETTINGS_FILE" ]; then
    mode_pre=$(jq -r '.permissions.defaultMode // empty' "$SETTINGS_FILE" 2>/dev/null) \
      || mode_pre=""
  fi

  # merge_default_mode returns 1 (user changed it by hand) and 2 (nothing to
  # do). The dispatcher runs under `set -e`, and a bare call returning non-zero
  # kills the shell mid-write — which left settings.json rewritten and the
  # manifest never updated, so forge disowned rules it had just added.
  local mode_rc=0
  merge_default_mode "$SETTINGS_FILE" "$desired_mode" "$prev_written" || mode_rc=$?
  if [ "$mode_rc" -eq 1 ]; then
    mode_note="defaultMode left as you set it"
  fi
  # Only claim the mode when forge actually wrote it.
  local mode_written=""
  [ "$mode_rc" -eq 0 ] && mode_written="$desired_mode"

  _permissions_update_manifest "$preset_name" "$ownership" "$mode_written" \
    "$exceptions" "$mode_pre" "$with_deny"

  local label count
  label=$(jq -r --arg id "$preset_name" '.presets[$id].label' "$PRESETS_FILE")
  count=$(echo "$allow" | jq 'length')

  if $json_mode; then
    jq -n \
      --arg preset "$preset_name" \
      --arg label "$label" \
      --argjson count "$count" \
      --argjson permissions "$allow" \
      --argjson ask "$ask" \
      --argjson deny "$deny" \
      '{applied: true, preset: $preset, label: $label, count: $count,
        permissions: $permissions, askRules: $ask, denyRules: $deny}'
  else
    ok "Applied ${_C_BOLD}${label}${_C_RST} — ${count} auto-approved, $(echo "$ask" | jq 'length') always ask."
    if [ -n "$mode_note" ]; then
      warn "$mode_note"
    fi
  fi

  # Without this the function inherits the exit status of whatever ran last,
  # and a successful apply reports failure.
  return 0
}

_permissions_print_diff() {
  local settings_file="$1" allow="$2" ask="$3" deny="$4"
  local removing="$5" newly_prompting="$6"

  local cur='[]' cur_ask='[]'
  if [ -f "$settings_file" ]; then
    cur=$(jq -c '.permissions.allow // []' "$settings_file" 2>/dev/null || echo '[]')
    cur_ask=$(jq -c '.permissions.ask // []' "$settings_file" 2>/dev/null || echo '[]')
  fi

  local add_n ask_n deny_n rm_n np_n
  add_n=$(jq -n --argjson a "$allow" --argjson c "$cur" '($a - $c) | length')
  ask_n=$(jq -n --argjson a "$ask" --argjson c "$cur_ask" '($a - $c) | length')
  deny_n=$(echo "$deny" | jq 'length')
  rm_n=$(echo "$removing" | jq 'length')
  np_n=$(echo "$newly_prompting" | jq 'length')

  printf "\n${_C_BOLD}Changes${_C_RST}\n"
  printf "  ${_C_GREEN}+%s${_C_RST} auto-approved   ${_C_YELLOW}+%s${_C_RST} always-ask   ${_C_RED}-%s${_C_RST} removed\n" \
    "$add_n" "$ask_n" "$rm_n"
  [ "$deny_n" -gt 0 ] && printf "  ${_C_RED}+%s${_C_RST} denied ${_C_DIM}(--with-deny)${_C_RST}\n" "$deny_n"

  if [ "$rm_n" -gt 0 ]; then
    printf "\n  ${_C_BOLD}No longer auto-approved${_C_RST} ${_C_DIM}(forge added these; they will prompt now)${_C_RST}\n"
    echo "$removing" | jq -r '.[]' | while IFS= read -r r; do
      printf "    ${_C_RED}-${_C_RST} %s\n" "$r"
    done
  fi

  if [ "$np_n" -gt 0 ]; then
    printf "\n  ${_C_BOLD}Newly prompting in 2.0${_C_RST} ${_C_DIM}(auto-approved before this release)${_C_RST}\n"
    echo "$newly_prompting" | jq -r '.[]' | while IFS= read -r r; do
      printf "    ${_C_YELLOW}?${_C_RST} %s\n" "$r"
    done
  fi
}

# ── Manifest update ──────────────────────────────────────────

_permissions_update_manifest() {
  local preset_name="$1"
  local ownership_json="$2"
  local mode_written="${3:-}"
  local exceptions="${4:-[]}"
  local mode_pre="${5:-}"
  local with_deny_flag="${6:-false}"

  [ -f "$MANIFEST_FILE" ] || return 0

  local presets_version
  presets_version=$(jq -r '.presets_version // "unknown"' \
    "$FORGE_SOURCE_DIR/templates/permission-presets.json" 2>/dev/null) \
    || presets_version="unknown"

  local tmp_manifest="${MANIFEST_FILE}.tmp"
  jq --arg preset "$preset_name" \
     --arg pv "$presets_version" \
     --arg mode "$mode_written" \
     --arg pre "$mode_pre" \
     --arg wd "$with_deny_flag" \
     --argjson own "$ownership_json" \
     --argjson ex "$exceptions" '
    .installed.permissions = {
      schema: 2,
      preset: $preset,
      presets_version: $pv,
      provenance: (.installed.permissions.provenance // "native"),
      # Remembered so a re-apply or a reinstall does not silently drop the deny
      # rules the user opted into. Without it --with-deny is a one-shot whose
      # removal is invisible, because removing what forge owns is correct.
      with_deny: ($wd == "true"),
      owned: $own.owned,
      adopted: $own.adopted,
      exceptions: $ex,
      default_mode: {
        written: (if $mode == "" then null else $mode end),
        # First recorded value wins: it is what was there before forge ever
        # touched the key.
        pre_existing: (
          if (.installed.permissions.default_mode.pre_existing) != null
          then .installed.permissions.default_mode.pre_existing
          elif $pre == "" then null
          else $pre end)
      }
    }
  ' "$MANIFEST_FILE" > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST_FILE"
}

# ── Help ─────────────────────────────────────────────────────

_permissions_help() {
  printf "\n${_C_BOLD}forge permissions${_C_RST} — manage Claude Code permission presets\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge permissions                      Show current preset\n"
  printf "  forge permissions --list               List available presets\n"
  printf "  forge permissions --preset <name>      Apply a preset\n"
  printf "  forge permissions --explain '<cmd>'    Show which rule decides a command\n"
  printf "  forge permissions --except <rule>      Record a rule forge must not apply\n"
  printf "\n${_C_BOLD}Flags:${_C_RST}\n"
  printf "  --diff        Preview the change without writing\n"
  printf "  --with-deny   Also write the deny list (off by default)\n"
  printf "  --yes         Skip the downgrade confirmation\n"
  printf "  --json        Machine-readable output\n"
  printf "\n${_C_BOLD}Presets:${_C_RST}\n"
  printf "  ${_C_BOLD}ask-before-changes${_C_RST}   Read-only auto-approved\n"
  printf "  ${_C_BOLD}auto-edit${_C_RST}            Read + write auto-approved\n"
  printf "  ${_C_BOLD}full-autonomy${_C_RST}        Dev commands auto-approved (recommended)\n"
  printf "\n${_C_DIM}Every preset also carries tier-independent \"ask\" rules: destructive and${_C_RST}\n"
  printf "${_C_DIM}credential-touching commands always prompt, at every trust level.${_C_RST}\n"
}
