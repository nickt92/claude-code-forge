#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Platform Utilities — cross-platform compatibility layer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supported: macOS, Linux
# Should work: Windows via WSL
# Not supported: Windows native, Git Bash

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
    *)       echo "unsupported" ;;
  esac
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

# Check if platform is supported and warn if not
check_platform() {
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    macos|linux)
      return 0
      ;;
    wsl)
      printf "${YELLOW:-}[WARN]${RST:-} Running under WSL — this should work but is not fully tested.\n"
      return 0
      ;;
    *)
      printf "${RED:-}[FAIL]${RST:-} Unsupported platform: %s. This installer supports macOS and Linux.\n" "$(uname -s)"
      return 1
      ;;
  esac
}