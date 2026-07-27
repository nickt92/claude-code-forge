#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cc-compat — check what Claude Code actually offers before writing to it
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# forge writes hooks, permission rules and a statusline into ~/.claude and then
# depends on Claude Code to honour them. Those couplings were undocumented and
# unverified, and it has cost twice already:
#
#   - a removed `claude plugins add` verb made `forge install` install zero
#     plugins and report success;
#   - an `if:` filter written at the wrong nesting level was silently discarded
#     for three releases while the release notes claimed a 95-99% reduction in
#     process spawns.
#
# Both were version-agnostic failures. The version had not moved in a way that
# mattered — a verb was gone, and a schema was stricter than assumed. So this
# checks capability, not just version.
#
# Required commands:
#   jq
#
# Usage:
#   source lib/cc-compat.sh
#   cc_compat_check            # gate: called before install mutates anything
#   cc_compat_report_json      # machine-readable, for doctor --json

CC_COMPAT_FILE="${CC_COMPAT_FILE:-${FORGE_SOURCE_DIR:-}/templates/cc-compat.json}"

# Features that could not be verified, recorded so callers can surface them
# rather than silently proceeding. Populated by cc_compat_check.
CC_COMPAT_SKIPPED=""

# ── Version handling ─────────────────────────────────────────

# Print the installed Claude Code version, or empty if it cannot be determined.
cc_detect_version() {
  command -v claude >/dev/null 2>&1 || return 1
  # `claude --version` prints e.g. "2.1.220 (Claude Code)"
  claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# cc_version_ge <a> <b> — is version a >= version b?
# Pure bash: no sort -V, which BSD and busybox handle inconsistently.
cc_version_ge() {
  local a="$1" b="$2"
  [ -n "$a" ] && [ -n "$b" ] || return 1

  local IFS=.
  # shellcheck disable=SC2206
  local av=($a) bv=($b)
  local i
  for i in 0 1 2; do
    local x="${av[$i]:-0}" y="${bv[$i]:-0}"
    # Strip anything non-numeric (pre-release suffixes etc.)
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$x" -gt "$y" ] 2>/dev/null; then return 0; fi
    if [ "$x" -lt "$y" ] 2>/dev/null; then return 1; fi
  done
  return 0
}

# ── Capability probes ────────────────────────────────────────

# List the subcommand names from a `--help` output.
#
# Commander formats them under a "Commands:" heading as
#     install|i [options] <plugin>    Install a plugin from ...
# so the name is the first token, and an alias may follow after a pipe. Wrapped
# description lines are indented further and must not be mistaken for commands.
_cc_help_subcommands() {
  awk '
    /^Commands:/       { in_cmds = 1; next }
    in_cmds && /^[A-Za-z]/ { in_cmds = 0 }      # next top-level section
    in_cmds && /^  [a-z]/  { print $1 }
  ' | sed 's/|.*//'
}

# Is a CLI verb still present? Walks the command tree by parsing --help at each
# level, so it is side-effect free and works on every install method — no verb
# is ever actually run.
#
# Returns 0 present, 1 absent, 2 could not tell.
cc_probe_cli_verb() {
  local verb="$1"
  command -v claude >/dev/null 2>&1 || return 2
  [ -n "$verb" ] || return 2

  local ctx=() word help
  # shellcheck disable=SC2206
  local words=($verb)

  for word in "${words[@]}"; do
    # ${arr[@]+"${arr[@]}"} — expanding an empty array is an unbound-variable
    # error under `set -u` on bash 3.2, which the forge dispatcher enables.
    # Same guard used in lib/plugins.sh and the arg parsers.
    help=$(claude ${ctx[@]+"${ctx[@]}"} --help 2>&1) || return 2
    [ -n "$help" ] || return 2

    if ! printf '%s\n' "$help" | _cc_help_subcommands | grep -qx "$word"; then
      return 1
    fi
    ctx+=("$word")
  done

  return 0
}

# ── The gate ─────────────────────────────────────────────────

# Verify Claude Code can support what forge is about to write.
# Called BEFORE install mutates anything — a failure here must cost the user
# nothing.
#
# Returns 0 to proceed (possibly with warnings), 1 to abort.
cc_compat_check() {
  local quiet="${1:-false}"
  CC_COMPAT_SKIPPED=""

  if [ ! -f "$CC_COMPAT_FILE" ]; then
    warn "Compatibility contract not found at $CC_COMPAT_FILE — skipping checks"
    return 0
  fi

  if ! command -v claude >/dev/null 2>&1; then
    forge_fail "Claude Code CLI not found"
    info "  Install it from https://docs.anthropic.com/en/docs/claude-code, then re-run."
    return 1
  fi

  local min tested detected
  min=$(jq -r '.min_claude_code // empty' "$CC_COMPAT_FILE")
  tested=$(jq -r '.tested_claude_code // empty' "$CC_COMPAT_FILE")
  detected=$(cc_detect_version)

  if [ -z "$detected" ]; then
    # Unknown is not the same as unsupported. Warn and continue rather than
    # blocking someone whose build reports a version we cannot parse.
    warn "Could not determine the Claude Code version — proceeding unverified"
    CC_COMPAT_SKIPPED="version-detection"
  elif [ -n "$min" ] && ! cc_version_ge "$detected" "$min"; then
    forge_fail "Claude Code $detected is older than the minimum forge supports ($min)"
    info "  Update Claude Code, then re-run 'forge install'."
    return 1
  elif [ -n "$tested" ] && ! cc_version_ge "$tested" "$detected"; then
    [ "$quiet" = true ] || warn "Claude Code $detected is newer than the last version forge was tested against ($tested)"
    [ "$quiet" = true ] || info "  Proceeding. Run 'forge doctor' afterwards to check nothing drifted."
  fi

  # CLI verbs are the failure mode that actually bit: present binary, correct
  # version, vanished verb.
  local verb missing_verbs=""
  while IFS= read -r verb; do
    [ -n "$verb" ] || continue
    cc_probe_cli_verb "$verb"
    case $? in
      0) ;;
      1) missing_verbs="${missing_verbs}${verb}, " ;;
      2) CC_COMPAT_SKIPPED="${CC_COMPAT_SKIPPED} verb-probe:${verb}" ;;
    esac
  done < <(jq -r '.requires.cli_verbs[]? // empty' "$CC_COMPAT_FILE")

  if [ -n "$missing_verbs" ]; then
    forge_fail "Claude Code no longer provides: ${missing_verbs%, }"
    info "  forge needs these to install plugins. This usually means Claude Code"
    info "  renamed a command. Please open an issue — forge needs updating."
    return 1
  fi

  return 0
}

# ── Reporting ────────────────────────────────────────────────

# Machine-readable state, for `forge doctor --json` and the desktop app.
cc_compat_report_json() {
  local detected min tested status
  detected=$(cc_detect_version)
  min=$(jq -r '.min_claude_code // empty' "$CC_COMPAT_FILE" 2>/dev/null)
  tested=$(jq -r '.tested_claude_code // empty' "$CC_COMPAT_FILE" 2>/dev/null)

  if [ -z "$detected" ]; then
    status="unknown"
  elif [ -n "$min" ] && ! cc_version_ge "$detected" "$min"; then
    status="unsupported"
  elif [ -n "$tested" ] && ! cc_version_ge "$tested" "$detected"; then
    status="untested"
  else
    status="ok"
  fi

  jq -n \
    --arg detected "${detected:-}" \
    --arg min "${min:-}" \
    --arg tested "${tested:-}" \
    --arg status "$status" \
    --arg skipped "${CC_COMPAT_SKIPPED# }" \
    '{
      detected: (if $detected == "" then null else $detected end),
      minimum: (if $min == "" then null else $min end),
      tested_against: (if $tested == "" then null else $tested end),
      status: $status,
      skipped: (if $skipped == "" then [] else ($skipped | split(" ")) end)
    }'
}
