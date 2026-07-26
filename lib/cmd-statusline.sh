#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# cmd-statusline — interactive legend for the forge status line
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Prints a colorful guide explaining every icon, zone, and color
# used in the Claude Code status line.
#
# Usage:
#   forge statusline

# ── Print helpers (namespaced to avoid collisions) ───────────

# _sl_icon <color> <icon_text> <label> <description>
_sl_icon() {
  local color="$1" icon="$2" label="$3" desc="$4"
  printf "  %s%-10s%s %-20s %s— %s%s\n" \
    "$color" "$icon" "${_SL_RST:-}" "$label" "${_SL_DIM:-}" "$desc" "${_SL_RST:-}"
}

# _sl_icon_bg <bg_color> <icon_text> <label> <description>
_sl_icon_bg() {
  local bg="$1" icon="$2" label="$3" desc="$4"
  printf "  %s %-10s %s %-17s %s— %s%s\n" \
    "$bg" "$icon" "${_SL_RST:-}" "$label" "${_SL_DIM:-}" "$desc" "${_SL_RST:-}"
}

cmd_statusline() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        printf "\n${_C_BOLD}forge statusline${_C_RST} — Interactive status line legend\n"
        printf "\n${_C_BOLD}Usage:${_C_RST}\n"
        printf "  forge statusline      Show the colorful icon/zone guide\n"
        printf "\nDisplays every icon, zone, and color used in the Claude Code status line.\n"
        return 0
        ;;
      *)
        forge_fail "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # ── Color palette (matches statusline-command.sh) ──────────
  local _SL_RST _SL_BOLD _SL_DIM
  local C_BRANCH C_DIRTY C_AHEAD C_BEHIND C_STASH C_WORKTREE
  local C_AGENT C_CTX C_CACHE
  local C_BAR_0 C_BAR_1 C_BAR_2 C_BAR_3 C_BAR_FRAME C_BAR_TRACK
  local C_RATE_OK C_RATE_MID C_RATE_HIGH
  local C_SPEED C_GOLD C_ADD C_DEL C_TEXT C_MUTED C_DIM_SEP
  local BG_OPUS BG_SONNET BG_HAIKU

  if [ "$_UI_USE_COLOR" = true ]; then
    _SL_RST=$'\033[0m'
    _SL_BOLD=$'\033[1m'
    _SL_DIM=$'\033[2m'

    # 256-color foregrounds (inline to avoid extra functions)
    _sl_fg()  { printf '\033[38;5;%sm' "$1"; }
    _sl_fbg() { printf '\033[1;97;48;5;%sm' "$1"; }

    C_BRANCH=$(_sl_fg 115)
    C_DIRTY=$(_sl_fg 215)
    C_AHEAD=$(_sl_fg 117)
    C_BEHIND=$(_sl_fg 203)
    C_STASH=$(_sl_fg 102)
    C_WORKTREE=$(_sl_fg 176)
    C_AGENT=$(_sl_fg 146)
    C_CTX=$(_sl_fg 75)
    C_CACHE=$(_sl_fg 71)
    C_BAR_0=$'\033[38;5;75m'
    C_BAR_1=$'\033[38;5;80m'
    C_BAR_2=$'\033[38;5;215m'
    C_BAR_3=$'\033[38;5;203m'
    C_BAR_FRAME=$(_sl_fg 243)
    C_BAR_TRACK=$(_sl_fg 237)
    C_RATE_OK=$(_sl_fg 114)
    C_RATE_MID=$(_sl_fg 221)
    C_RATE_HIGH=$(_sl_fg 203)
    C_SPEED=$(_sl_fg 114)
    C_GOLD=$(_sl_fg 179)
    C_ADD=$(_sl_fg 114)
    C_DEL=$(_sl_fg 203)
    C_TEXT=$(_sl_fg 188)
    C_MUTED=$(_sl_fg 102)
    C_DIM_SEP=$(_sl_fg 239)
    BG_OPUS=$(_sl_fbg 125)
    BG_SONNET=$(_sl_fbg 24)
    BG_HAIKU=$(_sl_fbg 23)
  else
    _SL_RST='' _SL_BOLD='' _SL_DIM=''
    C_BRANCH='' C_DIRTY='' C_AHEAD='' C_BEHIND='' C_STASH='' C_WORKTREE=''
    C_AGENT='' C_CTX='' C_CACHE=''
    C_BAR_0='' C_BAR_1='' C_BAR_2='' C_BAR_3='' C_BAR_FRAME='' C_BAR_TRACK=''
    C_RATE_OK='' C_RATE_MID='' C_RATE_HIGH=''
    C_SPEED='' C_GOLD='' C_ADD='' C_DEL='' C_TEXT='' C_MUTED='' C_DIM_SEP=''
    BG_OPUS='' BG_SONNET='' BG_HAIKU=''
  fi

  local SEP="${C_DIM_SEP}║${_SL_RST}"

  # ── Example status line ────────────────────────────────────
  banner "Statusline Guide"
  printf "\n"
  printf "  ┌─────────────────────────────────────────────────────────────────────────────────┐\n"
  printf "  │ %s🌿 feat/thing %s✦3 %s↑2%s  %s  %s %s Opus %s %s⬆ high%s  %s🤖 architect%s  %s  %s◈ %s▐%s████%s████%s████%s▍░░░░░░░░%s▌ %s%s62%%%s  %s💾 46%%%s  %s  %s🔋 48%% %s⚡ 342t/s%s  %s  %s💰 %s\$2.87%s · %s✏️  +342%s/%s−89%s · %s⏱️  32m%s │\n" \
    "${C_BRANCH}" "${C_DIRTY}" "${C_AHEAD}" "${_SL_RST}" \
    "${SEP}" "${BG_OPUS}" "" "${_SL_RST}" "${C_MUTED}" "${_SL_RST}" "${C_AGENT}" "${_SL_RST}" \
    "${SEP}" "${C_CTX}" "${C_BAR_FRAME}" "${C_BAR_0}" "${C_BAR_1}" "${C_BAR_2}" "${C_BAR_3}" "${C_BAR_TRACK}" "${C_BAR_FRAME}" "${_SL_BOLD}${C_BAR_1}" "${_SL_RST}" "${C_CACHE}" "${_SL_RST}" \
    "${SEP}" "${C_RATE_OK}" "${C_SPEED}" "${_SL_RST}" \
    "${SEP}" "${C_GOLD}" "${_SL_BOLD}" "${_SL_RST}" "${C_ADD}" "${_SL_RST}" "${C_DEL}" "${_SL_RST}" "${C_MUTED}" "${_SL_RST}"
  printf "  └─────────────────────────────────────────────────────────────────────────────────┘\n"

  # ── Zone 1: Git ────────────────────────────────────────────
  banner "Zone 1: Git"
  _sl_icon "${C_BRANCH}" "🌿" "Branch name" "current git branch (green = feature)"
  _sl_icon "${C_BRANCH}" "🌲" "Worktree branch" "pink when in a git worktree"
  _sl_icon "${C_MUTED}" "📂" "Working directory" "shown when not in a git repo"
  _sl_icon "${C_DIRTY}" "✦N" "Uncommitted changes" "staged + unstaged count"
  _sl_icon "${C_AHEAD}" "↑N" "Commits ahead" "local commits not yet pushed"
  _sl_icon "${C_BEHIND}" "↓N" "Commits behind" "remote commits not yet pulled"
  _sl_icon "${C_STASH}" "📦N" "Stash count" "git stash entries"
  _sl_icon "${_C_RED}" "REBASING" "Active git state" "also MERGING, CHERRY-PICK"

  # ── Zone 2: Model + Agent ──────────────────────────────────
  banner "Zone 2: Model + Agent"
  _sl_icon_bg "${BG_OPUS}" "🧠 Opus" "Opus model" "background: magenta"
  _sl_icon_bg "${BG_SONNET}" "🧠 Sonnet" "Sonnet model" "background: blue"
  _sl_icon_bg "${BG_HAIKU}" "🧠 Haiku" "Haiku model" "background: teal"
  _sl_icon "${C_MUTED}" "⬆ high" "Effort level" "reasoning depth: high / med / low"
  _sl_icon "${C_AGENT}" "🤖 name" "Active subagent" "shown during agent delegation"

  # ── Zone 3: Context Window ─────────────────────────────────
  banner "Zone 3: Context Window"
  _sl_icon "${C_CTX}" "◈" "Context section" "marker for context zone"
  printf "  %s▐%s████%s████%s██%s░░░░░░░░%s▌%s   Gradient bar       — blue→cyan→amber→red as usage increases\n" \
    "${C_BAR_FRAME}" "${C_BAR_0}" "${C_BAR_1}" "${C_BAR_2}" "${C_BAR_TRACK}" "${C_BAR_FRAME}" "${_SL_RST}"
  _sl_icon "${_SL_BOLD}" "62%" "Context used" "bold, color matches bar edge"
  _sl_icon "${C_CACHE}" "💾 46%" "Cache hit ratio" "higher = faster responses"
  _sl_icon "${C_RATE_HIGH}" "⚠ 200k+" "Context warning" "shown when exceeding 200k tokens"

  # ── Zone 4: Limits + Speed ─────────────────────────────────
  banner "Zone 4: Limits + Speed"
  _sl_icon "${C_RATE_OK}" "🔋 N%" "5-hour rate limit" "green <50%, yellow 50-80%, red 80%+"
  _sl_icon "${C_RATE_MID}" "📅 7d N%" "7-day rate limit" "Max plan usage, shown when ≥50%"
  _sl_icon "${C_SPEED}" "⚡ Nt/s" "Token speed" "generation throughput"

  # ── Zone 5: Session ────────────────────────────────────────
  banner "Zone 5: Session"
  _sl_icon "${C_TEXT}" "📝 name" "Session name" "from /rename or --name"
  _sl_icon "${C_GOLD}" "💰 \$N.NN" "Session cost" "accumulated API cost"
  _sl_icon "${C_ADD}" "✏️  +N" "Lines added" "green"
  _sl_icon "${C_DEL}" "   −N" "Lines removed" "red"
  _sl_icon "${C_MUTED}" "⏱️  Nm" "Session duration" "elapsed time"
  _sl_icon "${_SL_BOLD}" "◆ INS" "Vim mode" "INS/VIS/NOR/REP when active"

  # ── Color Key ──────────────────────────────────────────────
  banner "Colors"
  printf "  ${C_RATE_OK}Green${_SL_RST}    All clear / low usage\n"
  printf "  ${C_RATE_MID}Yellow${_SL_RST}   Moderate / attention\n"
  printf "  ${C_RATE_HIGH}Red${_SL_RST}      High / critical\n"
  printf "  ${_SL_BOLD}Bold${_SL_RST}     Important values (context %%, model name)\n"
  printf "\n"
}
