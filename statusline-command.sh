#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Premium Claude Code Status Line v8
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Note: we intentionally do NOT set -e or -o pipefail because
# this script must always produce output, even with partial data.
#
# Dependencies: jq, git (optional)
#
# Design principles:
#   - 5 logical zones: Git ║ Model+Agent ║ Context ║ Limits ║ Session
#   - Every segment leads with an icon for scanability
#   - ║ delimiters with generous padding between zones
#   - · separators within zones for related items
#   - Smooth gradient bar with sub-character precision
#   - Background-colored model badge
#   - Smart hiding: segments disappear when at default/zero
#
# Example:
#   🌿 feat/thing ✦6 ↑2  ║  🧠  Opus  🤖 architect  ║  ◈ 124k/200k ▐████████████▍░░░░░░░▌ 62% 🔄23%  ║  🔋 48% ⚡ 342t/s  ║  💰 $2.87 · ✏️ +342/−89 · ⏱️ 32m
#

# ── Dependency check ─────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "statusline: jq is required but not installed" >&2
  exit 1
fi

input=$(cat)

# ── JSON validation guard ────────────────────────────────────
if ! jq empty <<< "$input" 2>/dev/null; then
  printf "\033[90mstatusline: waiting for data\033[0m\n"
  exit 0
fi

# ── Color Palette ────────────────────────────────────────────
RST=$'\033[0m'
BOLD=$'\033[1m'

# 256-color foregrounds
fg()  { printf '\033[38;5;%sm' "$1"; }
bg()  { printf '\033[48;5;%sm' "$1"; }
fbg() { printf '\033[1;97;48;5;%sm' "$1"; }  # bold white on bg

# Semantic colors
C_BRANCH=$(fg 115)        # soft green — branch name
C_DIRTY=$(fg 215)         # amber — uncommitted work
C_AHEAD=$(fg 117)         # bright cyan — ahead
C_BEHIND=$(fg 203)        # red — behind
C_STASH=$(fg 102)         # gray — stashes
C_DIM=$(fg 239)           # dark gray — delimiters, low-priority
C_TEXT=$(fg 188)           # light gray — data values
C_MUTED=$(fg 102)         # gray — secondary text
C_AGENT=$(fg 146)         # lavender — agent name
C_WORKTREE=$(fg 176)      # pink — worktree name
C_CTX_ICON=$(fg 75)       # bright blue — context icon
C_CACHE=$(fg 71)          # green — cache indicator
C_GOLD=$(fg 179)          # gold — cost
C_ADD=$(fg 114)           # green — lines added
C_DEL=$(fg 203)           # red — lines removed
C_BAR_FRAME=$(fg 243)     # neutral gray — bar frame, doesn't compete with gradient
C_BAR_TRACK=$(fg 237)     # dark gray — empty bar

# Bar gradient (precomputed — avoids subshell per character)
C_BAR_0=$'\033[38;5;75m'   # blue (0-40%)
C_BAR_1=$'\033[38;5;80m'   # cyan (40-70%)
C_BAR_2=$'\033[38;5;215m'  # amber (70-90%)
C_BAR_3=$'\033[38;5;203m'  # red (90-100%)

# Rate limit colors
C_RATE_OK=$(fg 114)       # green
C_RATE_MID=$(fg 221)      # yellow
C_RATE_HIGH=$(fg 203)     # red
C_RATE_CRIT="${BOLD}$(fg 203)"  # bold red

# Speed colors
C_SPEED_FAST=$(fg 114)    # green
C_SPEED_MID=$(fg 102)     # gray
C_SPEED_SLOW=$(fg 215)    # amber

# Model badge backgrounds
BG_OPUS=$(fbg 125)        # deep magenta/rose
BG_SONNET=$(fbg 24)       # deep blue
BG_HAIKU=$(fbg 23)        # muted teal
BG_DEFAULT=$(fbg 236)     # subtle dark gray

# Block characters for sub-character bar precision
BLOCKS=("▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")

# ── Extract all JSON data in one jq call ─────────────────────
IFS='|' read -r cwd model_id model_display cost_usd duration_ms \
  lines_added lines_removed vim_mode exceeds_200k used_pct agent_name \
  ctx_size ctx_input ctx_output ctx_cache_create ctx_cache_read \
  remaining_pct rate_5h_pct rate_5h_resets session_id \
  wt_name total_output session_name rate_7d_pct rate_7d_resets \
  effort_level git_worktree < <(
  jq -r '[
    .workspace.current_dir // ".",
    .model.id // "",
    .model.display_name // "Claude",
    (.cost.total_cost_usd // 0 | tostring),
    (.cost.total_duration_ms // 0 | tostring),
    (.cost.total_lines_added // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    .vim.mode // "",
    (.exceeds_200k_tokens // false | tostring),
    (.context_window.used_percentage // -1 | tostring),
    .agent.name // "",
    (.context_window.context_window_size // 0 | tostring),
    (.context_window.current_usage.input_tokens // 0 | tostring),
    (.context_window.current_usage.output_tokens // 0 | tostring),
    (.context_window.current_usage.cache_creation_input_tokens // 0 | tostring),
    (.context_window.current_usage.cache_read_input_tokens // 0 | tostring),
    (.context_window.remaining_percentage // -1 | tostring),
    (.rate_limits.five_hour.used_percentage // -1 | tostring),
    (.rate_limits.five_hour.resets_at // 0 | tostring),
    .session_id // "",
    .worktree.name // "",
    (.context_window.total_output_tokens // 0 | tostring),
    .session_name // "",
    (.rate_limits.seven_day.used_percentage // -1 | tostring),
    (.rate_limits.seven_day.resets_at // 0 | tostring),
    .effort.level // "",
    (.workspace.git_worktree // false | tostring)
  ] | join("|")' <<< "$input" | tr -d '\r'
)

# ── Validate extraction ──────────────────────────────────────
if [[ -z "$model_id" ]] && [[ -z "$model_display" ]]; then
  printf "\033[90mstatusline: parsing…\033[0m\n"
  exit 0
fi

# ── Sanitize numeric inputs ─────────────────────────────────
to_int() { local v="${1%%.*}"; v="${v//[!0-9-]/}"; [[ "$v" =~ ^(-?[0-9]+) ]] && echo "${BASH_REMATCH[1]}" || echo 0; }

used_int=$(to_int "$used_pct")
remaining_int=$(to_int "$remaining_pct")
ctx_size_int=$(to_int "$ctx_size")
ctx_input_int=$(to_int "$ctx_input")
ctx_cache_create_int=$(to_int "$ctx_cache_create")
ctx_cache_read_int=$(to_int "$ctx_cache_read")
ctx_output_int=$(to_int "$ctx_output")
total_output_int=$(to_int "$total_output")
rate_7d_int=$(to_int "$rate_7d_pct")
rate_7d_resets_int=$(to_int "$rate_7d_resets")
lines_added_int=$(to_int "$lines_added")
lines_removed_int=$(to_int "$lines_removed")
dur_int=$(to_int "$duration_ms")
rate_5h_int=$(to_int "$rate_5h_pct")
rate_5h_resets_int=$(to_int "$rate_5h_resets")
read -r cost_cents cost_positive < <(
  awk -v c="${cost_usd:-0}" 'BEGIN { printf "%.0f %d", c * 100, (c > 0) ? 1 : 0 }'
)

# ── Context percentage ────────────────────────────────────────
# Trust Claude Code's used_percentage when available. Fall back to
# remaining_percentage, then to raw token computation as last resort.
# Note: ccstatusline computes its own % from contextLength/total instead
# of trusting used_percentage. We prefer the provider's authoritative value.
ctx_tokens=$(( ctx_input_int + ctx_output_int + ctx_cache_create_int + ctx_cache_read_int ))
has_ctx_data=false

if [ "$used_int" -ge 0 ]; then
  # Primary: Claude Code's own used_percentage
  has_ctx_data=true
elif [ "$remaining_int" -ge 0 ]; then
  # Fallback: derive from remaining_percentage
  used_int=$(( 100 - remaining_int ))
  has_ctx_data=true
elif [ "$ctx_tokens" -gt 0 ] && [ "$ctx_size_int" -gt 0 ]; then
  # Last resort: compute from raw tokens against full window size
  used_int=$(( ctx_tokens * 100 / ctx_size_int ))
  has_ctx_data=true
fi
[ "$used_int" -gt 100 ] && used_int=100
[ "$used_int" -lt 0 ] && used_int=0

# Precompute bar colors into an array indexed by bar position (0..bar_width-1)
# This avoids subshell spawning inside the bar loop
declare -a BAR_COLORS

# ── Epoch (single fork, reused for speed + rate countdown) ────
now_sec=$(date +%s)

# ── Token speed (rolling, via state file) ─────────────────────
tok_speed=""
if [ -n "$session_id" ] && [ "$total_output_int" -gt 0 ]; then
  safe_sid="${session_id//[^a-zA-Z0-9_-]/_}"
  state_file="${TMPDIR:-/tmp}/forge-sl-${safe_sid}"
  if [ -f "$state_file" ]; then
    IFS='|' read -r prev_ts prev_out < "$state_file"
    delta_sec=$(( now_sec - $(to_int "$prev_ts") ))
    delta_tok=$(( total_output_int - $(to_int "$prev_out") ))
    # Discard stale samples (>30s gap = terminal was backgrounded/locked)
    if [ "$delta_sec" -gt 0 ] && [ "$delta_sec" -le 30 ] && [ "$delta_tok" -gt 0 ]; then
      speed=$(( delta_tok / delta_sec ))
      [ "$speed" -gt 0 ] && tok_speed="$speed"
    fi
  fi
  printf '%s|%s' "$now_sec" "$total_output_int" > "$state_file" 2>/dev/null
fi

# ── Separators ───────────────────────────────────────────────
SEP=" ${C_DIM}║${RST} "        # zone delimiter
DOT=" ${C_DIM}·${RST} "        # within-zone separator

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ZONE 1: Git Context
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
git_status_output=$(git -C "$cwd" status --porcelain --branch 2>/dev/null | tr -d '\r' | head -52)

if [ -z "$git_status_output" ]; then
    git_seg="${C_DIM}📂 $(basename "$cwd")${RST}"
else
    branch_line="${git_status_output%%$'\n'*}"
    git_branch="${branch_line#\#\# }"
    git_branch="${git_branch%%...*}"
    [[ "$git_branch" == "No commits yet on "* ]] && git_branch="${git_branch#No commits yet on }"
    [[ "$git_branch" == "Initial commit on "* ]] && git_branch="${git_branch#Initial commit on }"

    # Ahead/behind
    ahead=0; behind=0
    [[ "$branch_line" == *"[ahead "* ]] && { a="${branch_line#*\[ahead }"; ahead=$(to_int "${a%%[],]*}"); }
    [[ "$branch_line" == *"behind "* ]] && { b="${branch_line#*behind }"; behind=$(to_int "${b%%[],]*}"); }

    # Dirty count
    dirty_lines=$(echo "$git_status_output" | tail -n +2)
    dirty_count=0
    [ -n "$dirty_lines" ] && dirty_count=$(echo "$dirty_lines" | wc -l | tr -d ' ')

    # Worktree detection — prefer workspace.git_worktree, fall back to worktree.name
    git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
    if [[ "$git_worktree" == "true" ]]; then
        tree_icon="🌲"
    elif [[ -n "$wt_name" ]] && [[ "$wt_name" != "null" ]]; then
        tree_icon="🌲"
    else
        tree_icon="🌿"
    fi

    # Detached HEAD
    if [[ "$git_branch" == "HEAD" ]] || [[ "$git_branch" == "(HEAD detached"* ]]; then
        short_sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null | tr -d '\r' || echo "???")
        git_branch="@${short_sha}"
    fi

    # Branch color (protected = red, develop = yellow, feature = green)
    if [[ "$git_branch" == "main" ]] || [[ "$git_branch" == "master" ]] || [[ "$git_branch" == @* ]]; then
        bc=$C_DEL  # red
    elif [[ "$git_branch" == "develop" ]]; then
        bc=$'\033[38;5;208m'  # orange — distinct from dirty amber (215)
    else
        bc=$C_BRANCH
    fi

    # Smart truncation
    display_branch="$git_branch"
    if [ ${#git_branch} -gt 30 ]; then
        prefix="${git_branch%%/*}"; rest="${git_branch#*/}"
        if [ "$prefix" != "$git_branch" ] && [ ${#prefix} -le 8 ]; then
            display_branch="${prefix}/…${rest: -20}"
        else
            display_branch="…${git_branch: -28}"
        fi
    fi

    # Git state
    git_state=""
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
        git_state=" ${BOLD}${C_DEL}REBASING${RST}"
    elif [ -f "$git_dir/MERGE_HEAD" ]; then
        git_state=" ${BOLD}${C_DEL}MERGING${RST}"
    elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
        git_state=" ${BOLD}${C_RATE_MID}CHERRY-PICK${RST}"
    fi

    # Stash count
    stash_count=$(git -C "$cwd" rev-list --walk-reflogs --count refs/stash 2>/dev/null || echo 0)

    # Assemble
    git_seg="${tree_icon} ${bc}${BOLD}${display_branch}${RST}"
    [ "$dirty_count" -gt 50 ] && git_seg="${git_seg} ${C_DIRTY}✦50+${RST}"
    [ "$dirty_count" -gt 0 ] && [ "$dirty_count" -le 50 ] && git_seg="${git_seg} ${C_DIRTY}✦${dirty_count}${RST}"
    [ "$ahead" -gt 0 ]       && git_seg="${git_seg} ${C_AHEAD}↑${ahead}${RST}"
    [ "$behind" -gt 0 ]      && git_seg="${git_seg} ${C_BEHIND}↓${behind}${RST}"
    [ "$stash_count" -gt 0 ] && git_seg="${git_seg} ${C_STASH}📦${stash_count}${RST}"
    git_seg="${git_seg}${git_state}"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ZONE 2: Model Badge + Agent
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ "$model_id" == *"opus"* ]]; then
    model_seg="${BG_OPUS} 🧠 Opus ${RST}"
elif [[ "$model_id" == *"sonnet"* ]]; then
    model_seg="${BG_SONNET} 🧠 Sonnet ${RST}"
elif [[ "$model_id" == *"haiku"* ]]; then
    model_seg="${BG_HAIKU} 🧠 Haiku ${RST}"
else
    model_seg="${BG_DEFAULT} 🧠 ${model_display} ${RST}"
fi

# Effort level indicator
effort_seg=""
if [[ -n "$effort_level" ]] && [[ "$effort_level" != "null" ]]; then
    case "$effort_level" in
        high)   effort_seg=" ${C_MUTED}⬆ high${RST}" ;;
        medium) effort_seg=" ${C_DIM}⬛ med${RST}" ;;
        low)    effort_seg=" ${C_DIM}⬇ low${RST}" ;;
    esac
fi

agent_seg=""
if [[ -n "$agent_name" ]] && [[ "$agent_name" != "null" ]]; then
    agent_seg=" 🤖 ${C_AGENT}${agent_name}${RST}"
elif [[ -n "$wt_name" ]] && [[ "$wt_name" != "null" ]]; then
    agent_seg=" 🌲 ${C_WORKTREE}${wt_name}${RST}"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ZONE 3: Context Window (hero section)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ctx_seg=""

if [ "$has_ctx_data" = true ]; then
    bar_width=20

    # Sub-character precision: fill in 8ths
    fill_eighths=$(( used_int * bar_width * 8 / 100 ))
    full_chars=$(( fill_eighths / 8 ))
    partial_eighth=$(( fill_eighths % 8 ))
    [ "$full_chars" -gt "$bar_width" ] && full_chars=$bar_width
    empty_chars=$(( bar_width - full_chars - (partial_eighth > 0 ? 1 : 0) ))
    [ "$empty_chars" -lt 0 ] && empty_chars=0

    # Precompute color for each bar position (no subshells in loop)
    for ((i=0; i<bar_width; i++)); do
        pos_pct=$(( (i + 1) * 100 / bar_width ))
        if   [ "$pos_pct" -ge 90 ]; then BAR_COLORS[$i]=$C_BAR_3
        elif [ "$pos_pct" -ge 70 ]; then BAR_COLORS[$i]=$C_BAR_2
        elif [ "$pos_pct" -ge 40 ]; then BAR_COLORS[$i]=$C_BAR_1
        else                              BAR_COLORS[$i]=$C_BAR_0
        fi
    done

    # Percentage color matches gradient at fill edge
    if   [ "$used_int" -ge 90 ]; then pct_color="${BOLD}${C_BAR_3}"
    elif [ "$used_int" -ge 70 ]; then pct_color="${BOLD}${C_BAR_2}"
    elif [ "$used_int" -ge 40 ]; then pct_color="${BOLD}${C_BAR_1}"
    else                               pct_color="${BOLD}${C_BAR_0}"
    fi

    # Build gradient bar using precomputed colors (zero subshells)
    bar=""
    for ((i=0; i<full_chars; i++)); do
        bar="${bar}${BAR_COLORS[$i]}█"
    done
    [ "$full_chars" -gt 0 ] && bar="${bar}${RST}"

    # Partial fill character at boundary
    if [ "$partial_eighth" -gt 0 ]; then
        bar="${bar}${BAR_COLORS[$full_chars]}${BLOCKS[$((partial_eighth - 1))]}${RST}"
    fi

    # Empty track (single color run, no per-char reset needed)
    if [ "$empty_chars" -gt 0 ]; then
        printf -v empty_str '%*s' "$empty_chars" ''
        empty_str="${empty_str// /░}"
        bar="${bar}${C_BAR_TRACK}${empty_str}${RST}"
    fi

    # Cache indicator
    cache_seg=""
    if [ "$ctx_cache_read_int" -gt 0 ] && [ "$ctx_tokens" -gt 0 ]; then
        cache_ratio=$(( ctx_cache_read_int * 100 / ctx_tokens ))
        [ "$cache_ratio" -gt 0 ] && cache_seg="  ${C_CACHE}💾 ${cache_ratio}%${RST}"
    fi

    # Warning
    ctx_warning=""
    [[ "$exceeds_200k" == "true" ]] && ctx_warning=" ${BOLD}${C_DEL}⚠ 200k+${RST}"

    printf -v pct_str '%3d%%' "$used_int"
    ctx_seg="${C_CTX_ICON}◈${RST} ${C_BAR_FRAME}▐${RST}${bar}${C_BAR_FRAME}▌${RST} ${pct_color}${pct_str}${RST}${cache_seg}${ctx_warning}"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ZONE 4: Limits + Speed
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
limits_parts=()

# Rate limit
if [ "$rate_5h_int" -ge 0 ]; then
    if [ "$rate_5h_int" -ge 90 ]; then
        rate_display="${C_RATE_CRIT}🔋 ${rate_5h_int}%${RST}"
    elif [ "$rate_5h_int" -ge 80 ]; then
        rate_display="${C_RATE_HIGH}🔋 ${rate_5h_int}%${RST}"
        # Countdown when critical
        if [ "$rate_5h_resets_int" -gt 0 ]; then
            rsec=$(( rate_5h_resets_int - now_sec ))
            if [ "$rsec" -gt 0 ]; then
                if [ "$rsec" -ge 3600 ]; then
                    rfmt="$(( rsec / 3600 ))h$(( (rsec % 3600) / 60 ))m"
                elif [ "$rsec" -ge 60 ]; then
                    rfmt="$(( rsec / 60 ))m"
                else
                    rfmt="${rsec}s"
                fi
                rate_display="${rate_display} ${C_DIM}↻${rfmt}${RST}"
            fi
        fi
    elif [ "$rate_5h_int" -ge 50 ]; then
        rate_display="${C_RATE_MID}🔋 ${rate_5h_int}%${RST}"
    else
        rate_display="${C_MUTED}🔋 ${rate_5h_int}%${RST}"
    fi
    [ -n "$rate_display" ] && limits_parts+=("$rate_display")
fi

# 7-day rate limit (Max plans) — show when >= 50% or when 5h is not available
if [ "$rate_7d_int" -ge 0 ] && [ "$rate_7d_int" -ge 50 ]; then
    if [ "$rate_7d_int" -ge 90 ]; then
        limits_parts+=("${C_RATE_CRIT}📅 7d ${rate_7d_int}%${RST}")
    elif [ "$rate_7d_int" -ge 80 ]; then
        limits_parts+=("${C_RATE_HIGH}📅 7d ${rate_7d_int}%${RST}")
    else
        limits_parts+=("${C_RATE_MID}📅 7d ${rate_7d_int}%${RST}")
    fi
fi

# Token speed — always show to prevent layout jitter
if [ -n "$tok_speed" ] && [ "$tok_speed" -ge 5 ]; then
    if [ "$tok_speed" -ge 100 ]; then
        limits_parts+=("${C_SPEED_FAST}⚡ ${tok_speed}t/s${RST}")
    elif [ "$tok_speed" -ge 30 ]; then
        limits_parts+=("${C_SPEED_MID}⚡ ${tok_speed}t/s${RST}")
    else
        limits_parts+=("${C_SPEED_SLOW}⚡ ${tok_speed}t/s${RST}")
    fi
elif [ "$total_output_int" -gt 0 ]; then
    limits_parts+=("${C_DIM}⚡ —${RST}")
fi

limits_seg=""
if [ ${#limits_parts[@]} -gt 0 ]; then
    limits_seg="${SEP}"
    for i in "${!limits_parts[@]}"; do
        [ "$i" -gt 0 ] && limits_seg="${limits_seg}${DOT}"
        limits_seg="${limits_seg}${limits_parts[$i]}"
    done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ZONE 5: Session Stats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
session_parts=()

# Session name (set via /rename or --name)
if [[ -n "$session_name" ]] && [[ "$session_name" != "null" ]]; then
    # Truncate long names
    display_name="$session_name"
    [ ${#session_name} -gt 20 ] && display_name="${session_name:0:18}…"
    session_parts+=("${C_TEXT}📝 ${display_name}${RST}")
fi

# Cost
if [ "$cost_positive" -eq 1 ]; then
    if [ "$cost_cents" -ge 100 ]; then
        printf -v cost_fmt '$%d.%02d' "$(( cost_cents / 100 ))" "$(( cost_cents % 100 ))"
    elif [ "$cost_cents" -gt 0 ]; then
        cost_fmt="${cost_cents}¢"
    else
        cost_fmt="<1¢"
    fi
    session_parts+=("${C_GOLD}💰 ${cost_fmt}${RST}")
fi

# Lines changed
if [ "$lines_added_int" -gt 0 ] || [ "$lines_removed_int" -gt 0 ]; then
    session_parts+=("${C_ADD}✏️ +${lines_added_int}${RST}${C_DIM}/${RST}${C_DEL}−${lines_removed_int}${RST}")
fi

# Duration
if [ "$dur_int" -gt 0 ]; then
    dur_sec=$(( dur_int / 1000 ))
    if [ "$dur_sec" -ge 3600 ]; then
        dur_fmt="$(( dur_sec / 3600 ))h$(( (dur_sec % 3600) / 60 ))m"
    elif [ "$dur_sec" -ge 60 ]; then
        dur_fmt="$(( dur_sec / 60 ))m"
    else
        dur_fmt="${dur_sec}s"
    fi
    session_parts+=("${C_MUTED}⏱️ ${dur_fmt}${RST}")
fi

# Vim mode
if [[ -n "$vim_mode" ]] && [[ "$vim_mode" != "null" ]]; then
    case "$vim_mode" in
        INSERT)  session_parts+=("${BOLD}${C_BAR_0}◆ INS${RST}") ;;
        VISUAL)  session_parts+=("${BOLD}${C_GOLD}◆ VIS${RST}") ;;
        REPLACE) session_parts+=("${BOLD}${C_DEL}◆ REP${RST}") ;;
        *)       session_parts+=("${BOLD}${C_ADD}◆ NOR${RST}") ;;
    esac
fi

session_seg=""
if [ ${#session_parts[@]} -gt 0 ]; then
    session_seg="${SEP}"
    for i in "${!session_parts[@]}"; do
        [ "$i" -gt 0 ] && session_seg="${session_seg}${DOT}"
        session_seg="${session_seg}${session_parts[$i]}"
    done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Assemble:  Git  ║  Model+Agent  ║  Context  ║  Limits  ║  Session
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Only show context separator when context data is available
ctx_with_sep=""
[ -n "$ctx_seg" ] && ctx_with_sep="${SEP}${ctx_seg}"

printf " %s%s%s%s%s%s%s\n" \
    "$git_seg" \
    "$SEP" \
    "$model_seg" \
    "$effort_seg" \
    "$agent_seg" \
    "$ctx_with_sep" \
    "${limits_seg}${session_seg}"
