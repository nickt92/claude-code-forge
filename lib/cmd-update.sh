#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-update — update forge from source repository
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Fetches latest changes from origin, ff-only merges, then
# re-runs install with the current persona.
#
# Usage:
#   forge update

cmd_update() {
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"

  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    printf "\n${_C_BOLD}forge update${_C_RST} — Update forge from source repository\n"
    printf "\n${_C_BOLD}Usage:${_C_RST}\n"
    printf "  forge update\n"
    printf "\nFetches latest changes and reinstalls with current persona.\n"
    return 0
  fi

  banner "Update"

  local source_dir="$FORGE_SOURCE_DIR"

  # Verify source dir is a git repo
  if [ ! -d "$source_dir/.git" ]; then
    forge_fail "Source directory is not a git repository: $source_dir"
    return 1
  fi

  # Check for clean working tree
  if ! git -C "$source_dir" diff --quiet 2>/dev/null || ! git -C "$source_dir" diff --cached --quiet 2>/dev/null; then
    forge_fail "Source directory has uncommitted changes: $source_dir"
    info "Commit or stash changes before updating"
    return 1
  fi

  # Verify on main or master branch
  local current_branch
  current_branch=$(git -C "$source_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
    warn "Source repo is on branch '$current_branch' (expected main or master)"
    info "Switch to main/master before updating, or continue at your own risk"
  fi

  # Record version before update
  local old_version="$FORGE_VERSION"

  # Fetch and merge
  step "Fetching"

  if ! git -C "$source_dir" fetch origin 2>/dev/null; then
    forge_fail "Failed to fetch from origin"
    return 1
  fi
  ok "Fetched latest from origin"

  step "Merging"

  local merge_output
  if ! merge_output=$(git -C "$source_dir" merge --ff-only 2>&1); then
    if echo "$merge_output" | grep -q "Already up to date"; then
      ok "Already up to date ($FORGE_VERSION)"
      return 0
    fi
    forge_fail "Fast-forward merge failed — resolve manually"
    info "$merge_output"
    return 1
  fi

  if echo "$merge_output" | grep -q "Already up to date"; then
    ok "Already up to date ($FORGE_VERSION)"
    return 0
  fi

  ok "Merged successfully"

  # Re-source manifest to pick up new version
  source "$FORGE_SOURCE_DIR/lib/manifest.sh"
  local new_version="$FORGE_VERSION"

  # Read current persona and plugin group from manifest
  local persona="senior-engineer"
  local plugin_group="full"
  if [ -f "$MANIFEST_FILE" ]; then
    persona=$(jq -r '.persona // "senior-engineer"' "$MANIFEST_FILE" 2>/dev/null)
    plugin_group=$(jq -r '.plugin_group // "full"' "$MANIFEST_FILE" 2>/dev/null)
  fi

  # Re-run install with current persona
  step "Reinstalling"

  source "$FORGE_SOURCE_DIR/lib/cmd-install.sh"
  local install_args=(--profile "$persona" --plugins "$plugin_group" --quiet)
  cmd_install "${install_args[@]}"

  # Report
  echo ""
  if [ "$old_version" != "$new_version" ]; then
    ok "Updated: ${old_version} → ${_C_BOLD}${new_version}${_C_RST}"
  else
    ok "Reinstalled: $new_version"
  fi
}
