#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard — effectiveness scoring engine
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Computes a weighted 0-100 effectiveness score across 6 dimensions.
# Each dimension returns 0-100, then weighted to produce final score.
#
# Dimensions:
#   Config completeness  25%  — CLAUDE.md exists + has content, profile.json valid
#   Rule coverage        20%  — Rules files present vs expected
#   Hook coverage        20%  — Hooks installed AND configured
#   Document chain       15%  — PROJECT/REQUIREMENTS/ROADMAP presence
#   Freshness            10%  — How recently configs were modified
#   Plugin alignment     10%  — Installed plugins match persona's recommended set
#
# Usage:
#   source lib/dashboard/score.sh
#   score_global "$global_json"          # outputs JSON with scores
#   score_repo "$repo_json" "$global_json"  # outputs JSON with repo score

# ── Score Dimensions (Global) ────────────────────────────────

# Config completeness: CLAUDE.md + profile.json
_score_config_completeness() {
  local global_json="$1"
  local score=0

  # CLAUDE.md exists (40 points)
  local claude_md_exists
  claude_md_exists=$(echo "$global_json" | jq -r '.claude_md.exists')
  [ "$claude_md_exists" = "true" ] && score=$((score + 40))

  # CLAUDE.md has substantial content — >50 lines (20 points)
  local claude_md_lines
  claude_md_lines=$(echo "$global_json" | jq -r '.claude_md.lines')
  [ "$claude_md_lines" -gt 50 ] 2>/dev/null && score=$((score + 20))

  # Persona is set and not "unknown" (20 points)
  local persona
  persona=$(echo "$global_json" | jq -r '.persona.persona')
  [ "$persona" != "unknown" ] && [ -n "$persona" ] && score=$((score + 20))

  # Axes are configured (20 points)
  local axes_count
  axes_count=$(echo "$global_json" | jq '.persona.axes | length')
  [ "$axes_count" -ge 4 ] 2>/dev/null && score=$((score + 20))

  echo "$score"
}

# Rule coverage: rules present vs expected set
_score_rule_coverage() {
  local global_json="$1"
  local rules_count
  rules_count=$(echo "$global_json" | jq -r '.rules.count')

  # Expected baseline: at least 5 rules for any persona
  local expected=5
  if [ "$rules_count" -ge "$expected" ] 2>/dev/null; then
    echo 100
  elif [ "$rules_count" -gt 0 ] 2>/dev/null; then
    echo $(( rules_count * 100 / expected ))
  else
    echo 0
  fi
}

# Hook coverage: hooks installed and configured in settings
_score_hook_coverage() {
  local global_json="$1"
  local hooks_count
  hooks_count=$(echo "$global_json" | jq '.hooks | length')

  # Expected: at least 6 hooks for a full setup
  local expected=6
  if [ "$hooks_count" -ge "$expected" ] 2>/dev/null; then
    echo 100
  elif [ "$hooks_count" -gt 0 ] 2>/dev/null; then
    echo $(( hooks_count * 100 / expected ))
  else
    echo 0
  fi
}

# Document chain: presence of PROJECT/REQUIREMENTS/ROADMAP (global = N/A, score from repos)
# For global: we score based on having forge-config.json properly set up
_score_doc_chain_global() {
  # Global doesn't have a doc chain; return 100 if config is set up
  local global_json="$1"
  local install_ts
  install_ts=$(echo "$global_json" | jq -r '.install.install_timestamp')
  if [ "$install_ts" != "unknown" ] && [ -n "$install_ts" ]; then
    echo 100
  else
    echo 50
  fi
}

# Freshness: how recently was the config modified
_score_freshness() {
  local global_json="$1"
  local install_ts
  install_ts=$(echo "$global_json" | jq -r '.install.install_timestamp')

  if [ "$install_ts" = "unknown" ] || [ -z "$install_ts" ]; then
    echo 50
    return
  fi

  # Parse date and compute days ago
  local date_part="${install_ts%%T*}"
  local install_epoch now_epoch
  if install_epoch=$(date -jf "%Y-%m-%d" "$date_part" +%s 2>/dev/null); then
    : # macOS
  elif install_epoch=$(date -d "$date_part" +%s 2>/dev/null); then
    : # GNU
  else
    echo 50
    return
  fi
  now_epoch=$(date +%s)
  local days_ago=$(( (now_epoch - install_epoch) / 86400 ))

  # Recently installed/updated = high freshness
  if [ "$days_ago" -le 7 ]; then
    echo 100
  elif [ "$days_ago" -le 30 ]; then
    echo 80
  elif [ "$days_ago" -le 90 ]; then
    echo 60
  elif [ "$days_ago" -le 180 ]; then
    echo 40
  else
    echo 20
  fi
}

# Plugin alignment: installed count vs expected for plugin group
_score_plugin_alignment() {
  local global_json="$1"
  local group count
  group=$(echo "$global_json" | jq -r '.plugins.group')
  count=$(echo "$global_json" | jq -r '.plugins.count')

  # Expected counts by group
  local expected=0
  case "$group" in
    full)     expected=18 ;;
    standard) expected=16 ;;
    minimal)  expected=6 ;;
    *)        expected=1 ;;
  esac

  if [ "$count" -ge "$expected" ] 2>/dev/null; then
    echo 100
  elif [ "$count" -gt 0 ] 2>/dev/null; then
    echo $(( count * 100 / expected ))
  else
    echo 0
  fi
}

# ── Score Dimensions (Per-Repo) ──────────────────────────────

_score_repo_config() {
  local repo_json="$1"
  local score=0

  # CLAUDE.md exists (50 points)
  local has_claude_md
  has_claude_md=$(echo "$repo_json" | jq -r '.claude_md.exists')
  [ "$has_claude_md" = "true" ] && score=$((score + 50))

  # CLAUDE.md has content (25 points)
  local lines
  lines=$(echo "$repo_json" | jq -r '.claude_md.lines')
  [ "$lines" -gt 10 ] 2>/dev/null && score=$((score + 25))

  # Has rules (25 points)
  local rules_count
  rules_count=$(echo "$repo_json" | jq -r '.rules.count')
  [ "$rules_count" -gt 0 ] 2>/dev/null && score=$((score + 25))

  echo "$score"
}

_score_repo_doc_chain() {
  local repo_json="$1"
  local score=0
  local dismissed
  dismissed=$(echo "$repo_json" | jq -r '.doc_chain.dismissed')

  # If dismissed, give partial credit (user made a deliberate choice)
  if [ "$dismissed" = "true" ]; then
    echo 60
    return
  fi

  local has_project has_requirements has_roadmap
  has_project=$(echo "$repo_json" | jq -r '.doc_chain.project_md')
  has_requirements=$(echo "$repo_json" | jq -r '.doc_chain.requirements_md')
  has_roadmap=$(echo "$repo_json" | jq -r '.doc_chain.roadmap_md')

  [ "$has_project" = "true" ] && score=$((score + 40))
  [ "$has_requirements" = "true" ] && score=$((score + 30))
  [ "$has_roadmap" = "true" ] && score=$((score + 30))

  echo "$score"
}

_score_repo_rules() {
  local repo_json="$1"
  local rules_count
  rules_count=$(echo "$repo_json" | jq -r '.rules.count')

  # For per-repo, having any rules is good; 3+ is excellent
  if [ "$rules_count" -ge 3 ] 2>/dev/null; then
    echo 100
  elif [ "$rules_count" -gt 0 ] 2>/dev/null; then
    echo $(( rules_count * 33 ))
  else
    echo 0
  fi
}

# ── Composite Scores ─────────────────────────────────────────

# Letter grade from numeric score
score_to_grade() {
  local score="$1"
  if [ "$score" -ge 90 ] 2>/dev/null; then
    echo "A"
  elif [ "$score" -ge 80 ] 2>/dev/null; then
    echo "B"
  elif [ "$score" -ge 70 ] 2>/dev/null; then
    echo "C"
  elif [ "$score" -ge 60 ] 2>/dev/null; then
    echo "D"
  else
    echo "F"
  fi
}

# Global effectiveness score (weighted composite)
score_global() {
  local global_json="$1"

  local config_score rule_score hook_score doc_score fresh_score plugin_score
  config_score=$(_score_config_completeness "$global_json")
  rule_score=$(_score_rule_coverage "$global_json")
  hook_score=$(_score_hook_coverage "$global_json")
  doc_score=$(_score_doc_chain_global "$global_json")
  fresh_score=$(_score_freshness "$global_json")
  plugin_score=$(_score_plugin_alignment "$global_json")

  # Weighted: config=25, rules=20, hooks=20, docs=15, fresh=10, plugins=10
  local total=$(( config_score * 25 + rule_score * 20 + hook_score * 20 + doc_score * 15 + fresh_score * 10 + plugin_score * 10 ))
  local final_score=$(( total / 100 ))
  local grade
  grade=$(score_to_grade "$final_score")

  jq -n \
    --argjson total "$final_score" \
    --arg grade "$grade" \
    --argjson config "$config_score" \
    --argjson rules "$rule_score" \
    --argjson hooks "$hook_score" \
    --argjson doc_chain "$doc_score" \
    --argjson freshness "$fresh_score" \
    --argjson plugins "$plugin_score" \
    '{
      total: $total,
      grade: $grade,
      dimensions: {
        config_completeness: { score: $config, weight: 25 },
        rule_coverage: { score: $rules, weight: 20 },
        hook_coverage: { score: $hooks, weight: 20 },
        doc_chain: { score: $doc_chain, weight: 15 },
        freshness: { score: $freshness, weight: 10 },
        plugin_alignment: { score: $plugins, weight: 10 }
      }
    }'
}

# Per-repo effectiveness score
score_repo() {
  local repo_json="$1"

  local config_score doc_score rules_score
  config_score=$(_score_repo_config "$repo_json")
  doc_score=$(_score_repo_doc_chain "$repo_json")
  rules_score=$(_score_repo_rules "$repo_json")

  # Weighted: config=50, doc_chain=30, rules=20
  local total=$(( config_score * 50 + doc_score * 30 + rules_score * 20 ))
  local final_score=$(( total / 100 ))
  local grade
  grade=$(score_to_grade "$final_score")

  jq -n \
    --argjson total "$final_score" \
    --arg grade "$grade" \
    --argjson config "$config_score" \
    --argjson doc_chain "$doc_score" \
    --argjson rules "$rules_score" \
    '{
      total: $total,
      grade: $grade,
      dimensions: {
        config: { score: $config, weight: 50 },
        doc_chain: { score: $doc_chain, weight: 30 },
        rules: { score: $rules, weight: 20 }
      }
    }'
}
