#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-init — initialize per-project forge config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Creates a .claude/ directory in the current working directory
# with project-level CLAUDE.md and rules. Does NOT modify global
# config (~/.claude/) or create hooks/settings (global only).
#
# Usage:
#   forge init --persona senior-engineer
#   forge init                            # uses current global persona
#   forge init --docs                     # scaffold document chain only
#   forge init --skip-docs                # skip document chain prompt

cmd_init() {
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"

  local persona=""
  local docs_only=false
  local skip_docs=false
  local project_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge init${_C_RST} — Initialize per-project forge config\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge init                           ${_C_DIM}Uses current global persona${_C_RST}\n"
        printf "  forge init ${_C_BOLD}--persona${_C_RST} <name>          ${_C_DIM}Specify persona${_C_RST}\n"
        printf "  forge init ${_C_BOLD}--dir${_C_RST} <path>              ${_C_DIM}Target directory (default: cwd)${_C_RST}\n"
        printf "  forge init ${_C_BOLD}--docs${_C_RST}                    ${_C_DIM}Scaffold document chain only${_C_RST}\n"
        printf "  forge init ${_C_BOLD}--skip-docs${_C_RST}               ${_C_DIM}Skip document chain prompt${_C_RST}\n"
        printf "\nCreates ${_C_BOLD}.claude/${_C_RST} with project-level CLAUDE.md and rules.\n"
        printf "${_C_DIM}Hooks and plugins are global — this sets project-level instructions only.${_C_RST}\n"
        printf "\n${_C_BOLD}Document chain${_C_RST} (optional):\n"
        printf "  ${_C_DIM}PROJECT.md      — project vision, constraints, stakeholders${_C_RST}\n"
        printf "  ${_C_DIM}REQUIREMENTS.md — scoped requirements with acceptance criteria${_C_RST}\n"
        printf "  ${_C_DIM}ROADMAP.md      — phased plan with progress tracking${_C_RST}\n"
        return 0
        ;;
      --persona)
        if [[ $# -lt 2 ]]; then
          fail "Missing persona name after --persona"
          return 1
        fi
        persona="$2"
        shift 2
        ;;
      --dir)
        if [[ $# -lt 2 ]]; then
          fail "Missing path after --dir"
          return 1
        fi
        project_dir="$2"
        shift 2
        ;;
      --docs)
        docs_only=true
        shift
        ;;
      --skip-docs)
        skip_docs=true
        shift
        ;;
      *)
        fail "Unknown option: $1"
        echo "Usage: forge init [--persona <name>] [--dir <path>] [--docs] [--skip-docs]"
        return 1
        ;;
    esac
  done

  project_dir="${project_dir:-$(pwd)}"
  local project_claude_dir="$project_dir/.claude"

  # --docs: scaffold document chain only, then return
  if [ "$docs_only" = true ]; then
    _init_scaffold_docs "$project_dir"
    return $?
  fi

  # Default to current global persona
  if [ -z "$persona" ]; then
    if [ -f "$CLAUDE_DIR/profile.json" ]; then
      persona=$(jq -r '.persona' "$CLAUDE_DIR/profile.json" 2>/dev/null)
    fi
    if [ -z "$persona" ]; then
      fail "No persona specified and no global profile found"
      echo "Usage: forge init --persona <name>"
      return 1
    fi
  fi

  local profile_file="$PROFILES_DIR/${persona}.json"
  if [ ! -f "$profile_file" ]; then
    fail "Unknown persona: $persona"
    return 1
  fi

  if [ -f "$project_claude_dir/CLAUDE.md" ]; then
    # Non-interactive when --dir is provided (programmatic usage)
    if [ "$project_dir" != "$(pwd)" ]; then
      : # proceed silently — caller controls overwrite decisions
    else
      read -p "  Project .claude/CLAUDE.md already exists. Overwrite? (y/N) " -n 1 -r
      echo
      [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
    fi
  fi

  banner "Project Init"

  # Create .claude directory
  mkdir -p "$project_claude_dir/rules"

  # Assemble CLAUDE.md
  assemble_claude_md "$profile_file" "$project_claude_dir/CLAUDE.md"

  # Copy rules
  local rule_count=0
  for rule_file in "$FORGE_SOURCE_DIR/templates/rules/"*.md; do
    [ -f "$rule_file" ] || continue
    cp "$rule_file" "$project_claude_dir/rules/$(basename "$rule_file")"
    ((rule_count++))
  done

  # Create .gitignore if not exists
  if [ ! -f "$project_claude_dir/.gitignore" ]; then
    cat > "$project_claude_dir/.gitignore" <<'GITIGNORE'
# Claude Code Forge — project-level .gitignore
# Uncomment lines to exclude from version control

# Exclude everything by default (opt-in)
# *
# !.gitignore
# !CLAUDE.md
# !rules/

# Or include everything (opt-out of specific files)
# plans/
# *.jsonl
GITIGNORE
  fi

  local lines label
  lines=$(wc -l < "$project_claude_dir/CLAUDE.md" | tr -d ' ')
  label=$(jq -r '.label' "$profile_file")

  ok "Project initialized with ${_C_BOLD}${label}${_C_RST}"
  kv "CLAUDE.md" "${lines} lines"
  kv "Rules" "${rule_count} copied"
  echo ""
  info "Hooks and plugins are global — this sets project-level instructions and rules only"

  # Document chain prompt (unless --skip-docs or already dismissed)
  if [ "$skip_docs" = true ]; then
    mkdir -p "$project_claude_dir"
    touch "$project_claude_dir/.docchain-skip"
  elif [ ! -f "$project_claude_dir/.docchain-skip" ]; then
    _init_prompt_docs "$project_dir"
  fi
}

# ── Document Chain Scaffolding ───────────────────────────────

_init_scaffold_docs() {
  local project_dir="$1"
  local template_dir="$FORGE_SOURCE_DIR/templates/document-chain"
  local created=0

  if [ ! -d "$template_dir" ]; then
    fail "Document chain templates not found at $template_dir"
    return 1
  fi

  for tmpl in PROJECT REQUIREMENTS ROADMAP; do
    local src="$template_dir/${tmpl}.template.md"
    local dst="$project_dir/${tmpl}.md"
    if [ -f "$dst" ]; then
      info "${tmpl}.md already exists — skipped"
    elif [ -f "$src" ]; then
      cp "$src" "$dst"
      ok "Created ${tmpl}.md"
      ((created++))
    else
      warn "${tmpl}.md template missing"
    fi
  done

  if [ "$created" -gt 0 ]; then
    echo ""
    info "Fill in the sections relevant to your project, delete the rest"
  elif [ "$created" -eq 0 ]; then
    info "All document chain files already exist"
  fi

  # Remove skip marker if it existed — user explicitly asked for docs
  rm -f "$project_dir/.claude/.docchain-skip" 2>/dev/null

  return 0
}

_init_prompt_docs() {
  local project_dir="$1"
  local project_claude_dir="$project_dir/.claude"

  # Skip if all three already exist
  if [ -f "$project_dir/PROJECT.md" ] && [ -f "$project_dir/REQUIREMENTS.md" ] && [ -f "$project_dir/ROADMAP.md" ]; then
    return 0
  fi

  echo ""
  printf "${_C_BOLD}Document chain${_C_RST} (optional):\n"
  printf "  ${_C_DIM}PROJECT.md      — project vision, constraints, stakeholders${_C_RST}\n"
  printf "  ${_C_DIM}REQUIREMENTS.md — scoped requirements with acceptance criteria${_C_RST}\n"
  printf "  ${_C_DIM}ROADMAP.md      — phased plan with progress tracking${_C_RST}\n"
  printf "  ${_C_DIM}Helps Claude maintain context across sessions.${_C_RST}\n"
  echo ""
  read -p "  Create document chain scaffolds? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    _init_scaffold_docs "$project_dir"
  else
    mkdir -p "$project_claude_dir"
    touch "$project_claude_dir/.docchain-skip"
    info "Skipped — run 'forge init --docs' later to scaffold"
  fi
}
