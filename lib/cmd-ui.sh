#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-ui — interactive web management interface
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Launches a local Node.js web server for browsing personas,
# switching config, running diagnostics, and building profiles.
# Node.js is scoped exclusively to this command.
#
# Usage:
#   forge ui              Start server + open browser
#   forge ui stop         Stop running server
#   forge ui status       Show running state + URL
#   forge ui --port N     Custom port
#   forge ui --no-open    Start without opening browser

_cmd_ui_load_deps() {
  source "$FORGE_SOURCE_DIR/lib/platform.sh"
}

# ── Lifecycle files ────────────────────────────────────────────

_ui_pid_file() { echo "$CLAUDE_DIR/forge-ui.pid"; }
_ui_port_file() { echo "$CLAUDE_DIR/forge-ui.port"; }
_ui_token_file() { echo "$CLAUDE_DIR/forge-ui.token"; }

# Check if PID is alive
_ui_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Clean up stale lifecycle files
_ui_cleanup_stale() {
  rm -f "$(_ui_pid_file)" "$(_ui_port_file)" "$(_ui_token_file)"
}

# Read running server info, returns 0 if running
_ui_read_running() {
  local pid_file="$(_ui_pid_file)"
  local port_file="$(_ui_port_file)"
  local token_file="$(_ui_token_file)"

  if [ ! -f "$pid_file" ]; then
    return 1
  fi

  UI_PID=$(cat "$pid_file" 2>/dev/null)
  if ! _ui_pid_alive "$UI_PID"; then
    _ui_cleanup_stale
    return 1
  fi

  UI_PORT=$(cat "$port_file" 2>/dev/null)
  UI_TOKEN=$(cat "$token_file" 2>/dev/null)
  return 0
}

# ── Subcommands ────────────────────────────────────────────────

_ui_stop() {
  if ! _ui_read_running; then
    info "No forge ui server is running"
    return 0
  fi

  kill "$UI_PID" 2>/dev/null
  # Wait briefly for graceful shutdown
  local waited=0
  while _ui_pid_alive "$UI_PID" && [ "$waited" -lt 10 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done

  if _ui_pid_alive "$UI_PID"; then
    kill -9 "$UI_PID" 2>/dev/null
  fi

  _ui_cleanup_stale
  ok "Server stopped (PID $UI_PID)"
}

_ui_status() {
  if _ui_read_running; then
    ok "Server running"
    kv "URL" "http://127.0.0.1:${UI_PORT}?token=${UI_TOKEN}"
    kv "PID" "$UI_PID"
    kv "Port" "$UI_PORT"
  else
    info "No forge ui server is running"
    info "Start with: forge ui"
  fi
}

_ui_start() {
  local port="${1:-0}"
  local do_open="${2:-true}"

  # Check Node.js is available
  if ! command -v node >/dev/null 2>&1; then
    fail "Node.js is required for forge ui but was not found"
    echo ""
    info "Install Node.js from: https://nodejs.org/"
    info "Or via package manager:"
    info "  macOS:  brew install node"
    info "  Ubuntu: sudo apt install nodejs"
    info "  Windows: winget install OpenJS.NodeJS"
    return 1
  fi

  # Check if already running
  if _ui_read_running; then
    ok "Server already running (PID $UI_PID)"
    local url="http://127.0.0.1:${UI_PORT}?token=${UI_TOKEN}"
    kv "URL" "$url"
    if [ "$do_open" = true ]; then
      open_browser "$url" 2>/dev/null || true
    fi
    return 0
  fi

  # Start server as background process
  local server_js="$FORGE_SOURCE_DIR/lib/forge-server.js"
  if [ ! -f "$server_js" ]; then
    fail "Server script not found: $server_js"
    return 1
  fi

  local tmpout
  tmpout=$(mktemp)

  FORGE_UI_PORT="$port" node "$server_js" > "$tmpout" 2>&1 &
  local server_pid=$!

  # Wait for server to start (up to 3s)
  local waited=0
  while [ "$waited" -lt 30 ]; do
    if [ -f "$(_ui_port_file)" ]; then
      break
    fi
    # Check if process died
    if ! _ui_pid_alive "$server_pid"; then
      fail "Server failed to start"
      cat "$tmpout" 2>/dev/null | while IFS= read -r line; do
        info "$line"
      done
      rm -f "$tmpout"
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  rm -f "$tmpout"

  if [ ! -f "$(_ui_port_file)" ]; then
    kill "$server_pid" 2>/dev/null
    fail "Server did not start within 3 seconds"
    return 1
  fi

  # Read the actual port and token
  _ui_read_running
  local url="http://127.0.0.1:${UI_PORT}?token=${UI_TOKEN}"

  ok "Server started (PID $UI_PID)"
  kv "URL" "$url"
  info "Stop with: forge ui stop"

  if [ "$do_open" = true ]; then
    if open_browser "$url" 2>/dev/null; then
      ok "Opened in browser"
    else
      info "Open manually: $url"
    fi
  fi
}

# ── Help ───────────────────────────────────────────────────────

_ui_help() {
  printf "\n${_C_BOLD}forge ui${_C_RST} — interactive web management interface\n"
  printf "\n${_C_BOLD}Usage:${_C_RST}\n"
  printf "  forge ui                  Start server and open browser\n"
  printf "  forge ui stop             Stop running server\n"
  printf "  forge ui status           Show running state and URL\n"
  printf "\n${_C_BOLD}Options:${_C_RST}\n"
  printf "  --port <N>                Use specific port (default: auto)\n"
  printf "  --no-open                 Start without opening browser\n"
  printf "  --help                    Show this help\n"
  printf "\n${_C_BOLD}Notes:${_C_RST}\n"
  printf "  Requires Node.js (v18+). Only forge ui uses Node — all\n"
  printf "  other forge commands remain pure bash.\n"
  printf "  Server binds to 127.0.0.1 only (local access).\n"
}

# ── Entry Point ────────────────────────────────────────────────

cmd_ui() {
  _cmd_ui_load_deps

  local subcmd=""
  local port=0
  local do_open=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      stop)
        subcmd="stop"
        shift
        ;;
      status)
        subcmd="status"
        shift
        ;;
      --port)
        if [[ $# -lt 2 ]]; then
          fail "Missing value after --port"
          return 1
        fi
        port="$2"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
          fail "Port must be a number"
          return 1
        fi
        shift 2
        ;;
      --no-open)
        do_open=false
        shift
        ;;
      --help|-h)
        _ui_help
        return 0
        ;;
      *)
        fail "Unknown option: $1"
        _ui_help
        return 1
        ;;
    esac
  done

  case "$subcmd" in
    stop)   _ui_stop ;;
    status) _ui_status ;;
    *)      _ui_start "$port" "$do_open" ;;
  esac
}
