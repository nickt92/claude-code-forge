#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-build — custom persona builder
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Interactive wizard by default; fully scriptable with flags
# (used by Forge Desktop's persona builder). Generates a
# custom-{name}.json profile in ~/.claude/profiles/.
#
# Usage:
#   forge build
#   forge build --name X --communication technical --autonomy high \
#     --workflow standard --depth practical [--quality core|engineering] \
#     [--plugins full|standard|minimal] [--switch|--no-switch] [--force]

cmd_build() {
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"

  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    printf "\n${_C_BOLD}forge build${_C_RST} — Create a custom persona profile\n"
    printf "\n${_C_BOLD}Usage:${_C_RST}\n"
    printf "  forge build                       Interactive wizard\n"
    printf "  forge build --name <name> \\\\\n"
    printf "    --communication plain|technical|expert \\\\\n"
    printf "    --autonomy guided|moderate|high \\\\\n"
    printf "    --workflow simplified|standard|advanced \\\\\n"
    printf "    --depth conceptual|practical|engineering \\\\\n"
    printf "    [--quality core|engineering]    Default: core\n"
    printf "    [--plugins full|standard|minimal] Default: full\n"
    printf "    [--switch|--no-switch]          Default: --no-switch\n"
    printf "    [--force]                       Overwrite existing custom persona\n"
    return 0
  fi

  # ── Flag parsing (presence of any flag selects non-interactive mode) ──
  local ni_name="" ni_comm="" ni_auto="" ni_work="" ni_depth=""
  local ni_quality="core" ni_plugins="full" ni_switch=0 ni_force=0
  local non_interactive=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --name)          ni_name="${2:-}"; non_interactive=1; shift 2 ;;
      --communication) ni_comm="${2:-}"; non_interactive=1; shift 2 ;;
      --autonomy)      ni_auto="${2:-}"; non_interactive=1; shift 2 ;;
      --workflow)      ni_work="${2:-}"; non_interactive=1; shift 2 ;;
      --depth)         ni_depth="${2:-}"; non_interactive=1; shift 2 ;;
      --quality)       ni_quality="${2:-}"; non_interactive=1; shift 2 ;;
      --plugins)       ni_plugins="${2:-}"; non_interactive=1; shift 2 ;;
      --switch)        ni_switch=1; non_interactive=1; shift ;;
      --no-switch)     ni_switch=0; non_interactive=1; shift ;;
      --force)         ni_force=1; non_interactive=1; shift ;;
      *)
        fail "Unknown option: $1 (see forge build --help)"
        return 1
        ;;
    esac
  done

  local name="" comm="" auto="" work="" depth="" quality='["core"]' plugin_group=""

  if [ "$non_interactive" -eq 1 ]; then
    # ── Non-interactive validation: fail fast, no prompts ──
    if [ -z "$ni_name" ]; then
      fail "--name is required in non-interactive mode"
      return 1
    fi
    if [[ ! "$ni_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
      fail "Invalid name '$ni_name'. Use letters, numbers, and hyphens. Must start with a letter."
      return 1
    fi
    if [ -f "$PROFILES_DIR/${ni_name}.json" ]; then
      fail "A built-in persona named '$ni_name' already exists."
      return 1
    fi
    if [ -f "$CLAUDE_DIR/profiles/custom-${ni_name}.json" ] || [ -f "$PROFILES_DIR/custom-${ni_name}.json" ]; then
      if [ "$ni_force" -ne 1 ]; then
        fail "Custom persona 'custom-${ni_name}' already exists. Pass --force to overwrite."
        return 1
      fi
    fi

    case "$ni_comm" in
      plain|technical|expert) ;;
      *) fail "--communication must be plain, technical, or expert (got '${ni_comm:-missing}')"; return 1 ;;
    esac
    case "$ni_auto" in
      guided|moderate|high) ;;
      *) fail "--autonomy must be guided, moderate, or high (got '${ni_auto:-missing}')"; return 1 ;;
    esac
    case "$ni_work" in
      simplified|standard|advanced) ;;
      *) fail "--workflow must be simplified, standard, or advanced (got '${ni_work:-missing}')"; return 1 ;;
    esac
    case "$ni_depth" in
      conceptual|practical|engineering) ;;
      *) fail "--depth must be conceptual, practical, or engineering (got '${ni_depth:-missing}')"; return 1 ;;
    esac
    case "$ni_quality" in
      core)        quality='["core"]' ;;
      engineering) quality='["core", "engineering"]' ;;
      *) fail "--quality must be core or engineering (got '$ni_quality')"; return 1 ;;
    esac
    case "$ni_plugins" in
      full|standard|minimal) ;;
      *) fail "--plugins must be full, standard, or minimal (got '$ni_plugins')"; return 1 ;;
    esac

    name="$ni_name"
    comm="$ni_comm"
    auto="$ni_auto"
    work="$ni_work"
    depth="$ni_depth"
    plugin_group="$ni_plugins"
  else
    banner "Custom Persona Builder"

    # ── Name ───────────────────────────────────────────────────
    step "Name"
    while true; do
      read -p "  Persona name (alphanumeric + hyphens): " name
      if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        warn "Invalid name. Use letters, numbers, and hyphens. Must start with a letter."
        continue
      fi
      if [ -f "$PROFILES_DIR/${name}.json" ]; then
        warn "A built-in persona with that name already exists."
        continue
      fi
      if [ -f "$CLAUDE_DIR/profiles/custom-${name}.json" ] || [ -f "$PROFILES_DIR/custom-${name}.json" ]; then
        read -p "  Custom persona 'custom-${name}' already exists. Overwrite? (y/N) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && continue
      fi
      break
    done

    # ── Communication ──────────────────────────────────────────
    step "Communication Style"
    printf "  ${_C_BOLD}1.${_C_RST} Plain      ${_C_DIM}Simple language, no jargon, explains everything${_C_RST}\n"
    printf "  ${_C_BOLD}2.${_C_RST} Technical  ${_C_DIM}Uses technical terms, assumes domain knowledge${_C_RST}\n"
    printf "  ${_C_BOLD}3.${_C_RST} Expert     ${_C_DIM}Dense, precise, assumes deep expertise${_C_RST}\n"
    while true; do
      read -p "  Your choice [1-3]: " choice
      case "$choice" in
        1) comm="plain"; break ;;
        2) comm="technical"; break ;;
        3) comm="expert"; break ;;
        *) echo "  Please enter 1, 2, or 3" ;;
      esac
    done

    # ── Autonomy ───────────────────────────────────────────────
    step "Autonomy Level"
    printf "  ${_C_BOLD}1.${_C_RST} Guided     ${_C_DIM}Checks in frequently, explains before acting${_C_RST}\n"
    printf "  ${_C_BOLD}2.${_C_RST} Moderate   ${_C_DIM}Balanced: proceeds on clear tasks, asks on ambiguity${_C_RST}\n"
    printf "  ${_C_BOLD}3.${_C_RST} High       ${_C_DIM}Acts independently, only asks on critical decisions${_C_RST}\n"
    while true; do
      read -p "  Your choice [1-3]: " choice
      case "$choice" in
        1) auto="guided"; break ;;
        2) auto="moderate"; break ;;
        3) auto="high"; break ;;
        *) echo "  Please enter 1, 2, or 3" ;;
      esac
    done

    # ── Workflow ───────────────────────────────────────────────
    step "Workflow Complexity"
    printf "  ${_C_BOLD}1.${_C_RST} Simplified ${_C_DIM}Minimal process, just get things done${_C_RST}\n"
    printf "  ${_C_BOLD}2.${_C_RST} Standard   ${_C_DIM}Balanced process with reasonable checks${_C_RST}\n"
    printf "  ${_C_BOLD}3.${_C_RST} Advanced   ${_C_DIM}Full engineering workflow with gates and reviews${_C_RST}\n"
    while true; do
      read -p "  Your choice [1-3]: " choice
      case "$choice" in
        1) work="simplified"; break ;;
        2) work="standard"; break ;;
        3) work="advanced"; break ;;
        *) echo "  Please enter 1, 2, or 3" ;;
      esac
    done

    # ── Depth ──────────────────────────────────────────────────
    step "Technical Depth"
    printf "  ${_C_BOLD}1.${_C_RST} Conceptual  ${_C_DIM}High-level explanations, focus on what not how${_C_RST}\n"
    printf "  ${_C_BOLD}2.${_C_RST} Practical   ${_C_DIM}Implementation-focused, code examples${_C_RST}\n"
    printf "  ${_C_BOLD}3.${_C_RST} Engineering ${_C_DIM}Deep technical detail, architecture rationale${_C_RST}\n"
    while true; do
      read -p "  Your choice [1-3]: " choice
      case "$choice" in
        1) depth="conceptual"; break ;;
        2) depth="practical"; break ;;
        3) depth="engineering"; break ;;
        *) echo "  Please enter 1, 2, or 3" ;;
      esac
    done

    # ── Quality ────────────────────────────────────────────────
    step "Quality Standards"
    read -p "  Include engineering quality standards (testing, perf, a11y)? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      quality='["core", "engineering"]'
    fi

    # ── Plugin Group ───────────────────────────────────────────
    step "Plugin Group"
    printf "  ${_C_BOLD}1.${_C_RST} Full      ${_C_DIM}All 18 plugins (engineering-focused)${_C_RST}\n"
    printf "  ${_C_BOLD}2.${_C_RST} Standard  ${_C_DIM}16 plugins (drops HR/legal and startup)${_C_RST}\n"
    printf "  ${_C_BOLD}3.${_C_RST} Minimal   ${_C_DIM}6 core plugins (lightweight)${_C_RST}\n"
    while true; do
      read -p "  Your choice [1-3]: " choice
      case "$choice" in
        1) plugin_group="full"; break ;;
        2) plugin_group="standard"; break ;;
        3) plugin_group="minimal"; break ;;
        *) echo "  Please enter 1, 2, or 3" ;;
      esac
    done
  fi

  # ── Generate Profile ───────────────────────────────────────
  local persona_key="custom-${name}"
  local user_profiles_dir="$CLAUDE_DIR/profiles"
  mkdir -p "$user_profiles_dir"
  local profile_file="$user_profiles_dir/${persona_key}.json"
  local display_name
  # Title-case the name (replace hyphens with spaces, capitalize words)
  display_name=$(echo "$name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')

  cat > "$profile_file" <<EOF
{
  "schema_version": 1,
  "persona": "${persona_key}",
  "label": "${display_name} (Custom)",
  "description": "Custom persona built with forge build",
  "axes": {
    "communication": "${comm}",
    "autonomy": "${auto}",
    "workflow": "${work}",
    "depth": "${depth}"
  },
  "quality": ${quality},
  "default_plugin_group": "${plugin_group}"
}
EOF

  # Validate by attempting assembly
  local temp_md
  temp_md="$(mktemp)"
  if ! assemble_claude_md "$profile_file" "$temp_md" 2>/dev/null; then
    fail "Profile generated but assembly failed — check axis values"
    rm -f "$temp_md" "$profile_file"
    return 1
  fi
  local lines
  lines=$(wc -l < "$temp_md" | tr -d ' ')
  rm -f "$temp_md"

  step "Summary"
  ok "Created ${_C_BOLD}${persona_key}${_C_RST} (${lines} lines when assembled)"
  info "Profile saved to: $profile_file"

  if [ "$non_interactive" -eq 1 ]; then
    if [ "$ni_switch" -eq 1 ]; then
      source "$FORGE_SOURCE_DIR/lib/cmd-switch.sh"
      cmd_switch "$persona_key"
    else
      info "To use later: forge switch ${persona_key}"
    fi
    return 0
  fi

  echo ""
  read -p "  Switch to this persona now? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    source "$FORGE_SOURCE_DIR/lib/cmd-switch.sh"
    cmd_switch "$persona_key"
  else
    echo ""
    info "To use later: forge switch ${persona_key}"
    info "To install:   forge install --profile ${persona_key}"
  fi
}
