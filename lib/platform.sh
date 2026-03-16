#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Platform Utilities — cross-platform compatibility layer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supported: macOS, Linux, Windows (Git Bash / MINGW / MSYS2)
# Should work: Windows via WSL

# Detect platform
detect_platform() {
  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin)  echo "macos" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    MINGW*|MSYS*)  echo "windows" ;;
    *)       echo "unsupported" ;;
  esac
}

# Quick boolean check for Windows (Git Bash)
is_windows() {
  [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]
}

# Platform-aware temp directory
get_temp_dir() {
  if [ -n "${TMPDIR:-}" ]; then
    echo "${TMPDIR%/}"
  elif [ -d "/tmp" ]; then
    echo "/tmp"
  else
    echo "."
  fi
}

# Platform-aware sed in-place (BSD vs GNU)
sed_inplace() {
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    macos)  sed -i '' "$@" ;;
    *)      sed -i "$@" ;;
  esac
}

# Platform-aware readlink (macOS lacks -f by default)
resolve_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target"
  elif command -v greadlink >/dev/null 2>&1; then
    greadlink -f "$target"
  elif readlink -f "$target" 2>/dev/null; then
    : # already printed
  else
    # Fallback: cd + pwd
    (cd "$(dirname "$target")" && echo "$(pwd)/$(basename "$target")")
  fi
}

# Windows jq compatibility — native Windows jq emits \r\n line endings;
# bash command substitution preserves the \r, breaking integer comparisons
# and path construction. This wrapper strips \r while preserving jq's exit code.
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* || "${OSTYPE:-}" == cygwin* ]]; then
  jq() { local _rc; command jq "$@" | tr -d '\r'; _rc=${PIPESTATUS[0]}; return "$_rc"; }
fi

# Convert bytes to human-readable format (KB/MB/GB)
format_bytes() {
  local bytes="$1"
  if [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1f GB\", $bytes/1073741824}"
  elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1f MB\", $bytes/1048576}"
  elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1f KB\", $bytes/1024}"
  else
    printf "%d bytes" "$bytes"
  fi
}

# Check if platform is supported and warn if not
check_platform() {
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    macos|linux)
      return 0
      ;;
    wsl)
      printf "${_C_YELLOW:-}[WARN]${_C_RST:-} Running under WSL — this should work but is not fully tested.\n"
      return 0
      ;;
    windows)
      printf "${_C_YELLOW:-}[WARN]${_C_RST:-} Running under Git Bash (Windows) — supported with minor limitations.\n"
      return 0
      ;;
    *)
      printf "${_C_RED:-}[FAIL]${_C_RST:-} Unsupported platform: %s. This installer supports macOS, Linux, and Windows (Git Bash).\n" "$(uname -s)"
      return 1
      ;;
  esac
}