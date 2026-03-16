#compdef forge
# Zsh completion for forge CLI
# Source this file or add to ~/.zshrc:
#   source ~/.claude/completions/forge.zsh

_forge() {
  local -a commands
  commands=(
    'build:Create a custom persona profile'
    'diff:Show differences between source and installed'
    'doctor:Run diagnostic health checks'
    'help:Show help'
    'init:Initialize per-project forge config'
    'install:Install or reinstall forge'
    'status:Show current installation status'
    'switch:Switch to a different persona'
    'update:Update forge from source repository'
    'version:Show forge version'
  )

  _arguments -C \
    '1:command:->command' \
    '*::arg:->args'

  case "$state" in
    command)
      _describe -t commands 'forge command' commands
      ;;
    args)
      case "${words[1]}" in
        switch)
          _forge_personas
          ;;
        install)
          _arguments \
            '--profile[Persona profile]:persona:_forge_personas' \
            '--plugins[Plugin group]:group:(full standard minimal)' \
            '--reconfigure[Re-run persona wizard]' \
            '--uninstall[Remove forge]' \
            '--check[Health checks only]' \
            '--quiet[Minimal output]' \
            '--dry-run[Show what would be installed]' \
            '--help[Show help]'
          ;;
        init)
          _arguments \
            '--persona[Persona to use]:persona:_forge_personas' \
            '--help[Show help]'
          ;;
        *)
          _arguments '--help[Show help]'
          ;;
      esac
      ;;
  esac
}

_forge_personas() {
  local -a personas
  local source_dir=""

  # Find source dir from manifest
  if [ -f "${HOME}/.claude/forge-backup/manifest.json" ] && command -v jq >/dev/null 2>&1; then
    source_dir=$(jq -r '.source_dir // ""' "${HOME}/.claude/forge-backup/manifest.json" 2>/dev/null)
  fi

  if [ -n "$source_dir" ] && [ -d "$source_dir/templates/profiles" ]; then
    for f in "$source_dir/templates/profiles"/*.json; do
      [ -f "$f" ] || continue
      personas+=("$(basename "$f" .json)")
    done
  fi

  # Also check user-space custom profiles
  if [ -d "${HOME}/.claude/profiles" ]; then
    for f in "${HOME}/.claude/profiles"/*.json; do
      [ -f "$f" ] || continue
      personas+=("$(basename "$f" .json)")
    done
  fi

  _describe -t personas 'persona' personas
}

_forge "$@"
