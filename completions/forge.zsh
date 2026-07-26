#compdef forge
# Zsh completion for forge CLI
# Source this file or add to ~/.zshrc:
#   source ~/.claude/completions/forge.zsh

_forge() {
  local -a commands
  commands=(
    'analyze:Extract codebase context as structured JSON'
    'audit:Audit CLAUDE.md quality for a repository'
    'build:Create a custom persona profile'
    'config:Get/set forge settings'
    'dashboard:Generate configuration dashboard'
    'diff:Show differences between source and installed'
    'doctor:Run diagnostic health checks'
    'export:Package forge installation into portable archive'
    'help:Show help'
    'init:Initialize per-project forge config'
    'install:Install or reinstall forge'
    'permissions:Manage Claude Code permission presets'
    'restore:Roll settings.json back to an earlier snapshot'
    'stats:Show installation statistics'
    'status:Show current installation status'
    'statusline:Show the interactive status line legend'
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
        audit)
          _arguments \
            '--json[Output structured JSON]' \
            '--help[Show help]' \
            '1:path:_directories'
          ;;
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
        stats)
          _arguments \
            '--security[Show security events only]' \
            '--sessions[Show session backups only]' \
            '--help[Show help]'
          ;;
        export)
          _arguments \
            {-o,--output}'[Output path]:path:_files -g "*.tar.gz"' \
            '--no-custom-profiles[Exclude custom personas]' \
            '--help[Show help]'
          ;;
        init)
          _arguments \
            '--persona[Persona to use]:persona:_forge_personas' \
            '--docs[Scaffold document chain only]' \
            '--skip-docs[Skip document chain prompt]' \
            '--help[Show help]'
          ;;
        dashboard)
          _arguments \
            '--json[Output JSON (default, backward compat)]' \
            '--help[Show help]'
          ;;
        doctor)
          _arguments \
            '--json[Output structured JSON]' \
            '--help[Show help]'
          ;;
        status)
          _arguments \
            '--json[Output structured JSON]' \
            '--help[Show help]'
          ;;
        config)
          _arguments \
            '1:subcommand:(get set list)' \
            '*::arg:->config_args'
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
