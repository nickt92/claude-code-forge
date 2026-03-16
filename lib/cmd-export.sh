#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-export — package forge installation into portable archive
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Creates a tar.gz archive containing the forge configuration
# suitable for backup or transfer to another machine.
#
# Usage:
#   forge export                          # default path
#   forge export -o custom-path.tar.gz    # custom output
#   forge export --no-custom-profiles     # exclude custom personas

# ── Helpers ──────────────────────────────────────────────────

_export_stage_files() {
  local staging_dir="$1"
  local include_custom_profiles="$2"

  local file_count=0

  # Profile and CLAUDE.md
  for f in profile.json CLAUDE.md; do
    if [ -f "$CLAUDE_DIR/$f" ]; then
      cp "$CLAUDE_DIR/$f" "$staging_dir/$f"
      file_count=$(( file_count + 1 ))
    fi
  done

  # statusline-command.sh
  if [ -f "$CLAUDE_DIR/statusline-command.sh" ]; then
    cp "$CLAUDE_DIR/statusline-command.sh" "$staging_dir/"
    file_count=$(( file_count + 1 ))
  fi

  # Settings additions from manifest (not raw settings.json)
  local settings_additions
  settings_additions=$(jq -r '.installed.settings_additions // {}' "$MANIFEST_FILE" 2>/dev/null)
  if [ "$settings_additions" != "{}" ] && [ -n "$settings_additions" ]; then
    echo "$settings_additions" > "$staging_dir/forge-settings-additions.json"
    file_count=$(( file_count + 1 ))
  fi

  # Directories: rules, hooks, scripts, lib
  local dir_counts=""
  for dir in rules hooks scripts lib; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
      local dir_file_count=0
      mkdir -p "$staging_dir/$dir"
      for f in "$CLAUDE_DIR/$dir"/*; do
        [ -f "$f" ] || continue
        cp "$f" "$staging_dir/$dir/"
        dir_file_count=$(( dir_file_count + 1 ))
        file_count=$(( file_count + 1 ))
      done
      if [ "$dir_file_count" -gt 0 ]; then
        dir_counts="${dir_counts}${dir}:${dir_file_count} "
      fi
    fi
  done

  # Completions
  if [ -d "$CLAUDE_DIR/completions" ]; then
    local comp_count=0
    mkdir -p "$staging_dir/completions"
    for f in "$CLAUDE_DIR/completions"/*; do
      [ -f "$f" ] || continue
      cp "$f" "$staging_dir/completions/"
      comp_count=$(( comp_count + 1 ))
      file_count=$(( file_count + 1 ))
    done
  fi

  # Custom profiles
  if [ "$include_custom_profiles" = true ] && [ -d "$CLAUDE_DIR/profiles" ]; then
    local custom_count=0
    for f in "$CLAUDE_DIR/profiles"/custom-*.json; do
      [ -f "$f" ] || continue
      mkdir -p "$staging_dir/profiles"
      cp "$f" "$staging_dir/profiles/"
      custom_count=$(( custom_count + 1 ))
      file_count=$(( file_count + 1 ))
    done
  fi

  echo "$file_count"
}

_export_write_meta() {
  local staging_dir="$1"

  local forge_version persona plugin_group
  forge_version=$(jq -r '.forge_version // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  persona=$(jq -r '.persona // "unknown"' "$MANIFEST_FILE" 2>/dev/null)
  plugin_group=$(jq -r '.plugin_group // "unknown"' "$MANIFEST_FILE" 2>/dev/null)

  local platform
  platform=$(uname -s | tr '[:upper:]' '[:lower:]')

  jq -n \
    --arg v "$forge_version" \
    --arg p "$persona" \
    --arg g "$plugin_group" \
    --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg pl "$platform" \
    '{forge_version: $v, manifest_version: 2, persona: $p, plugin_group: $g, export_timestamp: $t, platform: $pl}' \
    > "$staging_dir/forge-export-meta.json"
}

_export_create_archive() {
  local staging_dir="$1"
  local output_path="$2"
  local archive_name
  archive_name=$(basename "$staging_dir")

  local parent_dir
  parent_dir=$(dirname "$staging_dir")

  tar -czf "$output_path" -C "$parent_dir" "$archive_name"
}

# ── Main ─────────────────────────────────────────────────────

cmd_export() {
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  local output_path=""
  local include_custom_profiles=true

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge export${_C_RST} — Package forge installation into portable archive\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge export                          # default output path\n"
        printf "  forge export -o custom.tar.gz         # custom output path\n"
        printf "  forge export --no-custom-profiles     # exclude custom personas\n"
        return 0
        ;;
      -o|--output)
        if [ $# -lt 2 ]; then
          fail "Missing path after $1"
          return 1
        fi
        output_path="$2"
        shift 2
        ;;
      --no-custom-profiles)
        include_custom_profiles=false
        shift
        ;;
      *)
        fail "Unknown option: $1"
        echo "Usage: forge export [-o path.tar.gz] [--no-custom-profiles] [--help]"
        return 1
        ;;
    esac
  done

  if [ ! -f "$MANIFEST_FILE" ]; then
    fail "Forge is not installed (no manifest found)"
    info "Run: forge install"
    return 1
  fi

  banner "Export"

  # Determine persona for default filename
  local persona
  persona=$(jq -r '.persona // "forge"' "$MANIFEST_FILE" 2>/dev/null)
  local timestamp_slug
  timestamp_slug=$(date +%Y%m%d)

  if [ -z "$output_path" ]; then
    output_path="./forge-export-${persona}-${timestamp_slug}.tar.gz"
  fi

  # Create staging directory
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
  local tmp_base
  tmp_base=$(get_temp_dir)
  local staging_dir="${tmp_base}/forge-export-${persona}-${timestamp_slug}"
  mkdir -p "$staging_dir"

  # Stage files
  local file_count
  file_count=$(_export_stage_files "$staging_dir" "$include_custom_profiles")

  # Write metadata
  _export_write_meta "$staging_dir"

  # Display what was staged
  local label="unknown"
  if [ -f "$CLAUDE_DIR/profile.json" ]; then
    label=$(jq -r '.label // .persona // "unknown"' "$CLAUDE_DIR/profile.json" 2>/dev/null)
  fi
  ok "Profile: $label ($persona)"

  for dir in rules hooks scripts; do
    if [ -d "$staging_dir/$dir" ]; then
      local count=0
      for f in "$staging_dir/$dir"/*; do
        [ -f "$f" ] && ((count++))
      done
      [ "$count" -gt 0 ] && ok "$dir: $count files"
    fi
  done

  if [ -d "$staging_dir/profiles" ]; then
    local custom_count=0
    for f in "$staging_dir/profiles"/*; do
      [ -f "$f" ] && custom_count=$(( custom_count + 1 ))
    done
    [ "$custom_count" -gt 0 ] && ok "Custom profiles: $custom_count files"
  fi

  # Create archive
  _export_create_archive "$staging_dir" "$output_path"

  # Cleanup staging dir
  rm -rf "$staging_dir"

  # Show result with archive size
  local archive_size
  if archive_size=$(stat -f "%z" "$output_path" 2>/dev/null); then
    : # macOS
  elif archive_size=$(stat -c "%s" "$output_path" 2>/dev/null); then
    : # GNU
  else
    archive_size=0
  fi

  local human_size
  human_size=$(format_bytes "$archive_size")

  echo ""
  ok "Exported to $output_path ($human_size)"
}
