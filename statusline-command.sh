#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Premium Claude Code Status Line v4
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Note: we intentionally do NOT set -e or -o pipefail because
# this script must always produce output, even with partial data.
#
# Dependencies: jq, git (optional)
#
# Git segment:
#   🌿 feat/thing ✦3 ↑2↓1 📦1   (dirty, ahead/behind, stashes)
#   🔗 feat/thing                 (linked worktree, clean)
#
# Full layout:
#   🌿 branch ✦3 ↑2 | 🧠 Opus | 🤖 agent | ▐████░░░░▌ 42% | 💰 38¢ | ✏️ +156 −23 | ⏱️ 12m
#

# ── Dependency check ─────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "statusline: jq is required but not installed" >&2
  exit 1
fi

input=$(cat)

# ── JSON validation guard ────────────────────────────────────
if ! echo "$input" | jq empty 2>/dev/null; then
  printf "\033[90mstatusline: waiting for data\033[0m\n"
  exit 0
fi

# ── Colors ───────────────────────────────────────────────────
RST=$'\033[0m'
DIM=$'\033[90m'
WHITE=$'\033[97m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'

# ── Extract all JSON data in one jq call ─────────────────────
# Uses | delimiter (not tab) — bash collapses consecutive tabs,
# which breaks empty fields like vim_mode.
IFS='|' read -r cwd model_id model_display cost_usd duration_ms \
  lines_added lines_removed vim_mode exceeds_200k used_pct agent_name < <(
  echo "$input" | jq -r '[
    .workspace.current_dir // ".",
    .model.id // "",
    .model.display_name // "Claude",
    (.cost.total_cost_usd // 0 | tostring),
    (.cost.total_duration_ms // 0 | tostring),
    (.cost.total_lines_added // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    .vim.mode // "",
    (.exceeds_200k_tokens // false | tostring),
    (.context_window.used_percentage // 0 | tostring),
    .agent.name // ""
  ] | join("|")' | tr -d '\r'
)

# ── Sanitize numeric inputs ─────────────────────────────────
to_int() { local v="${1%%.*}"; v="${v//[!0-9-]/}"; echo "${v:-0}"; }

used_int=$(to_int "$used_pct")
lines_added_int=$(to_int "$lines_added")
lines_removed_int=$(to_int "$lines_removed")
dur_int=$(to_int "$duration_ms")
cost_cents=$(awk -v c="${cost_usd:-0}" 'BEGIN { printf "%.0f", c * 100 }')
cost_positive=$(awk -v c="${cost_usd:-0}" 'BEGIN { print (c > 0) ? 1 : 0 }')

# ── Git segment (rich) ──────────────────────────────────────
git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r' || echo "")

if [ -z "$git_branch" ]; then
    git_seg="${DIM}🌿 —${RST}"
else
    # Worktree detection: linked worktree when git-dir != git-common-dir
    # Uses --absolute-git-dir (Git 2.13+) so state detection works
    # regardless of the process working directory.
    git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
    git_common=$(cd "$cwd" && git rev-parse --git-common-dir 2>/dev/null)
    # Resolve git_common to absolute for reliable comparison
    [ -n "$git_common" ] && [[ "$git_common" != /* ]] && git_common="$cwd/$git_common"
    if [ "$git_dir" != "$git_common" ]; then
        tree_icon="🔗"  # linked worktree
    else
        tree_icon="🌿"  # main tree
    fi

    # Detached HEAD: show short SHA instead of "HEAD"
    if [[ "$git_branch" == "HEAD" ]]; then
        short_sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null | tr -d '\r' || echo "???")
        git_branch="@${short_sha}"
    fi

    # Branch color: red for protected/detached, yellow for develop, blue for feature
    if [[ "$git_branch" == "main" ]] || [[ "$git_branch" == "master" ]] || [[ "$git_branch" == @* ]]; then
        branch_color=$RED
    elif [[ "$git_branch" == "develop" ]]; then
        branch_color=$YELLOW
    else
        branch_color=$BLUE
    fi

    # Smart truncation: preserve prefix for conventional branches
    display_branch="$git_branch"
    if [ ${#git_branch} -gt 30 ]; then
        prefix="${git_branch%%/*}"
        rest="${git_branch#*/}"
        if [ "$prefix" != "$git_branch" ] && [ ${#prefix} -le 8 ]; then
            display_branch="${prefix}/…${rest: -20}"
        else
            display_branch="…${git_branch: -28}"
        fi
    fi

    # Git state: detect merge/rebase/cherry-pick in progress
    git_state=""
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
        git_state=" ${RED}REBASING${RST}"
    elif [ -f "$git_dir/MERGE_HEAD" ]; then
        git_state=" ${RED}MERGING${RST}"
    elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
        git_state=" ${YELLOW}CHERRY-PICK${RST}"
    fi

    # Dirty state (capped at 50 for perf — shows 50+ if truncated)
    porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null | tr -d '\r' | head -50)
    dirty_count=0
    if [ -n "$porcelain" ]; then
        dirty_count=$(echo "$porcelain" | wc -l | tr -d ' ')
    fi

    # Ahead/behind upstream
    ahead=0; behind=0
    if ab_output=$(git -C "$cwd" rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null | tr -d '\r') && [ -n "$ab_output" ]; then
        ahead="${ab_output%%[[:space:]]*}"
        behind="${ab_output##*[[:space:]]}"
    fi

    # Stash count (capped at 100 for perf)
    stash_count=$(git -C "$cwd" stash list 2>/dev/null | tr -d '\r' | head -100 | wc -l | tr -d ' ')

    # Assemble git segment
    git_seg="${branch_color}${tree_icon} ${display_branch}${RST}"
    indicators=""

    if [ "$dirty_count" -ge 50 ]; then
        indicators="${indicators} ${YELLOW}✦${dirty_count}+${RST}"
    elif [ "$dirty_count" -gt 0 ]; then
        indicators="${indicators} ${YELLOW}✦${dirty_count}${RST}"
    fi

    [ "$ahead" -gt 0 ]       && indicators="${indicators} ${CYAN}↑${ahead}${RST}"
    [ "$behind" -gt 0 ]      && indicators="${indicators} ${RED}↓${behind}${RST}"
    [ "$stash_count" -gt 0 ] && indicators="${indicators} ${DIM}📦${stash_count}${RST}"

    git_seg="${git_seg}${indicators}${git_state}"
fi

# ── Model ────────────────────────────────────────────────────
if [[ "$model_id" == *"opus"* ]]; then
    model_seg="🧠 ${BOLD}${RED}Opus${RST}"
elif [[ "$model_id" == *"sonnet"* ]]; then
    model_seg="🧠 ${BOLD}${CYAN}Sonnet${RST}"
elif [[ "$model_id" == *"haiku"* ]]; then
    model_seg="🧠 ${BOLD}${GREEN}Haiku${RST}"
else
    model_seg="🧠 ${WHITE}${model_display}${RST}"
fi

# ── Agent (shown when running with --agent or agent settings) ─
agent_seg=""
if [[ -n "$agent_name" ]] && [[ "$agent_name" != "null" ]]; then
    agent_seg=" ${DIM}│${RST} 🤖 ${CYAN}${agent_name}${RST}"
fi

# ── Context bar (16-char, bookended) ─────────────────────────
bar_width=16

# Clamp to 0-100 for display
[ "$used_int" -gt 100 ] && used_int=100
[ "$used_int" -lt 0 ] && used_int=0

filled=$(( used_int * bar_width / 100 ))
[ "$filled" -gt "$bar_width" ] && filled=$bar_width
[ "$filled" -lt 0 ] && filled=0
empty=$(( bar_width - filled ))

if [ "$used_int" -ge 90 ]; then
    bar_fill_color=$RED; pct_color=$RED
elif [ "$used_int" -ge 70 ]; then
    bar_fill_color=$YELLOW; pct_color=$YELLOW
else
    bar_fill_color=$GREEN; pct_color=$GREEN
fi

bar=""
for ((i=0; i<filled; i++)); do bar="${bar}█"; done
for ((i=0; i<empty; i++)); do bar="${bar}░"; done

ctx_warning=""
if [[ "$exceeds_200k" == "true" ]]; then
    ctx_warning=" ${RED}⚠️${RST}"
fi

ctx_seg="${DIM}▐${RST}${bar_fill_color}${bar}${RST}${DIM}▌${RST} ${pct_color}${used_int}%${RST}${ctx_warning}"

# ── Cost ─────────────────────────────────────────────────────
cost_seg=""
if [ "$cost_positive" -eq 1 ]; then
    if [ "$cost_cents" -ge 100 ]; then
        cost_fmt=$(printf '$%.2f' "$cost_usd")
    elif [ "$cost_cents" -gt 0 ]; then
        cost_fmt="${cost_cents}¢"
    else
        cost_fmt="<1¢"
    fi

    if [ "$cost_cents" -ge 500 ]; then
        cost_seg=" ${DIM}│${RST} 💰 ${RED}${cost_fmt}${RST}"
    elif [ "$cost_cents" -ge 100 ]; then
        cost_seg=" ${DIM}│${RST} 💰 ${YELLOW}${cost_fmt}${RST}"
    else
        cost_seg=" ${DIM}│${RST} 💰 ${DIM}${cost_fmt}${RST}"
    fi
fi

# ── Lines changed ────────────────────────────────────────────
lines_seg=""
if [ "$lines_added_int" -gt 0 ] || [ "$lines_removed_int" -gt 0 ]; then
    lines_seg=" ${DIM}│${RST} ✏️ ${GREEN}+${lines_added_int}${RST} ${RED}−${lines_removed_int}${RST}"
fi

# ── Session duration ─────────────────────────────────────────
duration_seg=""
if [ "$dur_int" -gt 0 ]; then
    dur_sec=$(( dur_int / 1000 ))
    if [ "$dur_sec" -ge 3600 ]; then
        dur_h=$(( dur_sec / 3600 ))
        dur_m=$(( (dur_sec % 3600) / 60 ))
        dur_fmt="${dur_h}h${dur_m}m"
    elif [ "$dur_sec" -ge 60 ]; then
        dur_m=$(( dur_sec / 60 ))
        dur_fmt="${dur_m}m"
    else
        dur_fmt="${dur_sec}s"
    fi
    duration_seg=" ${DIM}│${RST} ⏱️ ${DIM}${dur_fmt}${RST}"
fi

# ── Vim mode ─────────────────────────────────────────────────
vim_seg=""
if [[ -n "$vim_mode" ]] && [[ "$vim_mode" != "null" ]]; then
    case "$vim_mode" in
        INSERT)  vim_seg=" ${DIM}│${RST} ${GREEN}INS${RST}" ;;
        VISUAL)  vim_seg=" ${DIM}│${RST} ${YELLOW}VIS${RST}" ;;
        REPLACE) vim_seg=" ${DIM}│${RST} ${RED}REP${RST}" ;;
        *)       vim_seg=" ${DIM}│${RST} ${BLUE}NOR${RST}" ;;
    esac
fi

# ── Assemble ─────────────────────────────────────────────────
printf "%s ${DIM}│${RST} %s%s ${DIM}│${RST} %s%s%s%s%s\n" \
    "$git_seg" \
    "$model_seg" \
    "$agent_seg" \
    "$ctx_seg" \
    "$cost_seg" \
    "$lines_seg" \
    "$duration_seg" \
    "$vim_seg"