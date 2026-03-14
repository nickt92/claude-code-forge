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

cmd_init() {
  source "$FORGE_SOURCE_DIR/lib/assembly.sh"
  source "$FORGE_SOURCE_DIR/lib/forge-inventory.sh"

  local persona=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge init${_C_RST} — Initialize per-project forge config\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge init                           ${_C_DIM}Uses current global persona${_C_RST}\n"
        printf "  forge init ${_C_BOLD}--persona${_C_RST} <name>          ${_C_DIM}Specify persona${_C_RST}\n"
        printf "\nCreates ${_C_BOLD}.claude/${_C_RST} with project-level CLAUDE.md and rules.\n"
        printf "${_C_DIM}Hooks and plugins are global — this sets project-level instructions only.${_C_RST}\n"
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
      *)
        fail "Unknown option: $1"
        echo "Usage: forge init [--persona <name>]"
        return 1
        ;;
    esac
  done

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

  local project_dir="$(pwd)"
  local project_claude_dir="$project_dir/.claude"

  if [ -f "$project_claude_dir/CLAUDE.md" ]; then
    read -p "  Project .claude/CLAUDE.md already exists. Overwrite? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
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
}
