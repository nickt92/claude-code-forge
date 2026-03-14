#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# UI Library — Homebrew-inspired output for Claude Code Forge
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Centralized colors, emojis, spinners, and progress counters.
# Designed for clean, grouped output (~35 lines for a full install).
#
# Usage:
#   source lib/ui.sh
#
# Environment:
#   UI_QUIET=true    — suppress all output except fail() and warn()
#   NO_COLOR=1       — disable colors (also auto-detected from TERM/TTY)
#
# All functions are plain bash — tests can override by redefining after source.

# ── TTY & Color Detection ────────────────────────────────────
_UI_IS_TTY=false
[ -t 1 ] && _UI_IS_TTY=true

_UI_USE_COLOR=true
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || [ "$_UI_IS_TTY" = false ]; then
  _UI_USE_COLOR=false
fi

# ── Colors (disabled when NO_COLOR or non-TTY) ──────────────
if [ "$_UI_USE_COLOR" = true ]; then
  _C_BOLD=$'\033[1m'
  _C_DIM=$'\033[2m'
  _C_RED=$'\033[31m'
  _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'
  _C_CYAN=$'\033[36m'
  _C_RST=$'\033[0m'
else
  _C_BOLD='' _C_DIM='' _C_RED='' _C_GREEN=''
  _C_YELLOW='' _C_CYAN='' _C_RST=''
fi

# ── Quiet Mode ───────────────────────────────────────────────
_ui_quiet() { [ "${UI_QUIET:-}" = true ]; }

# ── Debug Mode ───────────────────────────────────────────────
_ui_debug() { [ "${UI_DEBUG:-}" = true ]; }

debug() {
  _ui_debug || return 0
  printf "${_C_DIM}[debug] %s${_C_RST}\n" "$1" >&2
}

# ── Public API ───────────────────────────────────────────────

# App header with hammer emoji
banner() {
  _ui_quiet && return 0
  local title="$1"
  printf "\n%s %s\n" "🔨" "${_C_BOLD}${title}${_C_RST}"
}

# Section header: ==> message
step() {
  _ui_quiet && return 0
  printf "\n${_C_BOLD}==>${_C_RST} ${_C_BOLD}%s${_C_RST}\n" "$1"
}

# Success: ✅  message
ok() {
  _ui_quiet && return 0
  printf "✅  %s\n" "$1"
}

# Warning: ⚠️  message (always prints, even in quiet)
warn() {
  printf "⚠️  %s\n" "$1"
}

# Error: ❌  message (always prints, even in quiet)
fail() {
  printf "❌  %s\n" "$1"
}

# Dim secondary text
info() {
  _ui_quiet && return 0
  printf "   ${_C_DIM}%s${_C_RST}\n" "$1"
}

# ── Spinner ──────────────────────────────────────────────────
# Usage: spin "message" command args...
# On TTY: shows braille spinner. On pipe/CI: "message... done"
_UI_SPINNER_PID=""

_spin_cleanup() {
  if [ -n "$_UI_SPINNER_PID" ] && kill -0 "$_UI_SPINNER_PID" 2>/dev/null; then
    kill "$_UI_SPINNER_PID" 2>/dev/null
    wait "$_UI_SPINNER_PID" 2>/dev/null
  fi
  _UI_SPINNER_PID=""
}

_spin_loop() {
  local msg="$1"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  while true; do
    printf "\r  %s %s" "${frames[$i]}" "$msg"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.1
  done
}

spin() {
  local msg="$1"
  shift

  local errfile
  errfile=$(mktemp)

  if [ "$_UI_IS_TTY" = true ] && ! _ui_quiet; then
    _spin_loop "$msg" &
    _UI_SPINNER_PID=$!
    # Run command, capture exit code + stderr
    local rc=0
    "$@" >/dev/null 2>"$errfile" || rc=$?
    _spin_cleanup
    # Clear spinner line
    printf "\r\033[K"
    if [ "$rc" -ne 0 ]; then
      debug "Command failed (rc=$rc): $(cat "$errfile")"
    fi
    rm -f "$errfile"
    return $rc
  else
    # Non-TTY fallback
    if ! _ui_quiet; then
      printf "  %s... " "$msg"
    fi
    local rc=0
    "$@" >/dev/null 2>"$errfile" || rc=$?
    if ! _ui_quiet; then
      if [ "$rc" -eq 0 ]; then
        printf "done\n"
      else
        printf "failed\n"
      fi
    fi
    if [ "$rc" -ne 0 ]; then
      debug "Command failed (rc=$rc): $(cat "$errfile")"
    fi
    rm -f "$errfile"
    return $rc
  fi
}

# ── Progress Counter ─────────────────────────────────────────
# Usage:
#   progress_start 18 "Installing plugins"
#   progress_tick    # call N times
#   progress_done "18 plugins installed"
#
# NOTE: Single-instance only — nested progress_start calls will
# corrupt the outer counter. Use sequentially, not nested.
_UI_PROGRESS_TOTAL=0
_UI_PROGRESS_CURRENT=0
_UI_PROGRESS_MSG=""

progress_start() {
  _UI_PROGRESS_TOTAL="$1"
  _UI_PROGRESS_MSG="$2"
  _UI_PROGRESS_CURRENT=0
  if ! _ui_quiet; then
    if [ "$_UI_IS_TTY" = true ]; then
      printf "  %s [0/%d]" "$_UI_PROGRESS_MSG" "$_UI_PROGRESS_TOTAL"
    else
      printf "  %s..." "$_UI_PROGRESS_MSG"
    fi
  fi
}

progress_tick() {
  _UI_PROGRESS_CURRENT=$(( _UI_PROGRESS_CURRENT + 1 ))
  if [ "$_UI_IS_TTY" = true ] && ! _ui_quiet; then
    printf "\r\033[K  %s [%d/%d]" "$_UI_PROGRESS_MSG" "$_UI_PROGRESS_CURRENT" "$_UI_PROGRESS_TOTAL"
  fi
}

progress_done() {
  local summary="$1"
  if ! _ui_quiet; then
    if [ "$_UI_IS_TTY" = true ]; then
      printf "\r\033[K"
    else
      printf " done\n"
    fi
  fi
  ok "$summary"
}

