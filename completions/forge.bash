#!/bin/bash
# Bash completion for forge CLI
# Source this file or add to ~/.bashrc:
#   source ~/.claude/completions/forge.bash

_forge() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="analyze audit build config dashboard diff doctor export help init install permissions restore stats status statusline switch update version"

  case "$prev" in
    forge)
      COMPREPLY=($(compgen -W "$commands" -- "$cur"))
      return 0
      ;;
    switch)
      # Complete persona names from profiles directory
      local profiles_dir=""
      local source_dir=""

      # Try to find source dir from manifest
      if [ -f "${HOME}/.claude/forge-backup/manifest.json" ] && command -v jq >/dev/null 2>&1; then
        source_dir=$(jq -r '.source_dir // ""' "${HOME}/.claude/forge-backup/manifest.json" 2>/dev/null)
      fi

      if [ -n "$source_dir" ] && [ -d "$source_dir/templates/profiles" ]; then
        profiles_dir="$source_dir/templates/profiles"
      fi

      if [ -n "$profiles_dir" ]; then
        local personas=""
        for f in "$profiles_dir"/*.json; do
          [ -f "$f" ] || continue
          local name
          name="$(basename "$f" .json)"
          personas="$personas $name"
        done
        # Also check user-space custom profiles
        if [ -d "${HOME}/.claude/profiles" ]; then
          for f in "${HOME}/.claude/profiles"/*.json; do
            [ -f "$f" ] || continue
            local name
            name="$(basename "$f" .json)"
            personas="$personas $name"
          done
        fi
        COMPREPLY=($(compgen -W "$personas" -- "$cur"))
      fi
      return 0
      ;;
    install)
      COMPREPLY=($(compgen -W "--profile --plugins --reconfigure --uninstall --check --quiet --dry-run --help" -- "$cur"))
      return 0
      ;;
    --profile)
      # Same persona completion as switch
      local profiles_dir=""
      local source_dir=""
      if [ -f "${HOME}/.claude/forge-backup/manifest.json" ] && command -v jq >/dev/null 2>&1; then
        source_dir=$(jq -r '.source_dir // ""' "${HOME}/.claude/forge-backup/manifest.json" 2>/dev/null)
      fi
      if [ -n "$source_dir" ] && [ -d "$source_dir/templates/profiles" ]; then
        profiles_dir="$source_dir/templates/profiles"
      fi
      if [ -n "$profiles_dir" ]; then
        local personas=""
        for f in "$profiles_dir"/*.json; do
          [ -f "$f" ] || continue
          personas="$personas $(basename "$f" .json)"
        done
        if [ -d "${HOME}/.claude/profiles" ]; then
          for f in "${HOME}/.claude/profiles"/*.json; do
            [ -f "$f" ] || continue
            personas="$personas $(basename "$f" .json)"
          done
        fi
        COMPREPLY=($(compgen -W "$personas" -- "$cur"))
      fi
      return 0
      ;;
    --plugins)
      COMPREPLY=($(compgen -W "full standard minimal" -- "$cur"))
      return 0
      ;;
    stats)
      COMPREPLY=($(compgen -W "--security --sessions --help" -- "$cur"))
      return 0
      ;;
    export)
      COMPREPLY=($(compgen -W "-o --output --no-custom-profiles --help" -- "$cur"))
      return 0
      ;;
    init)
      COMPREPLY=($(compgen -W "--persona --docs --skip-docs --help" -- "$cur"))
      return 0
      ;;
    audit)
      COMPREPLY=($(compgen -W "--json --help" -- "$cur"))
      return 0
      ;;
    dashboard)
      COMPREPLY=($(compgen -W "--json --help" -- "$cur"))
      return 0
      ;;
    doctor)
      COMPREPLY=($(compgen -W "--json --help" -- "$cur"))
      return 0
      ;;
    status)
      COMPREPLY=($(compgen -W "--json --help" -- "$cur"))
      return 0
      ;;
    config)
      COMPREPLY=($(compgen -W "get set list --help" -- "$cur"))
      return 0
      ;;
    *)
      # Complete flags for current subcommand
      if [ "${COMP_WORDS[1]}" = "install" ]; then
        COMPREPLY=($(compgen -W "--profile --plugins --reconfigure --uninstall --check --quiet --dry-run --help" -- "$cur"))
      fi
      return 0
      ;;
  esac
}

complete -F _forge forge
