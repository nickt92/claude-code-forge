#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Dashboard — HTML generation engine
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Produces a self-contained HTML dashboard with embedded CSS, JS,
# and JSON data. Zero external dependencies or network calls.
#
# Structured as emit_*() functions, each outputting one HTML section
# via heredoc. The only dynamic injection is the JSON data blob.
#
# Usage:
#   source lib/dashboard/generate.sh
#   generate_dashboard "$dashboard_json" "$output_path"

# ── CSS: Design System ───────────────────────────────────────

_emit_styles() {
  cat <<'STYLES'
<style>
  /* ── Reset & Base ─────────────────────────────── */
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    /* Colors — colorblind-safe palette */
    --c-success: #1a9a6b;
    --c-success-bg: #e6f7f0;
    --c-warning: #b8860b;
    --c-warning-bg: #fdf6e3;
    --c-danger: #c53030;
    --c-danger-bg: #fef2f2;
    --c-accent: #6d5cdb;
    --c-accent-bg: #f0eeff;

    --c-bg: #ffffff;
    --c-bg-secondary: #f8f9fa;
    --c-bg-card: #ffffff;
    --c-text: #1a1a2e;
    --c-text-secondary: #6b7280;
    --c-text-dim: #9ca3af;
    --c-border: #e5e7eb;
    --c-border-hover: #d1d5db;

    /* Typography */
    --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    --font-mono: "SF Mono", "Fira Code", "Fira Mono", Menlo, monospace;

    /* Spacing (8px base) */
    --sp-1: 4px; --sp-2: 8px; --sp-3: 12px; --sp-4: 16px;
    --sp-6: 24px; --sp-8: 32px; --sp-12: 48px; --sp-16: 64px;

    /* Borders */
    --r-sm: 4px; --r-md: 8px; --r-lg: 12px; --r-xl: 16px;

    /* Shadows */
    --shadow-sm: 0 1px 2px rgba(0,0,0,.05);
    --shadow-md: 0 4px 6px rgba(0,0,0,.07);
    --shadow-lg: 0 10px 15px rgba(0,0,0,.1);

    /* Transitions */
    --ease: cubic-bezier(0.33, 1, 0.68, 1);
    --t-fast: 150ms; --t-med: 250ms; --t-slow: 400ms;
  }

  /* ── Dark Mode ────────────────────────────────── */
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --c-bg: #0f1117;
      --c-bg-secondary: #1a1d2e;
      --c-bg-card: #1e2130;
      --c-text: #e5e7eb;
      --c-text-secondary: #9ca3af;
      --c-text-dim: #6b7280;
      --c-border: #2d3148;
      --c-border-hover: #3d4260;
      --c-success-bg: #0d2818;
      --c-warning-bg: #2a1f00;
      --c-danger-bg: #2d0a0a;
      --c-accent-bg: #1a1533;
      --shadow-sm: 0 1px 2px rgba(0,0,0,.2);
      --shadow-md: 0 4px 6px rgba(0,0,0,.3);
      --shadow-lg: 0 10px 15px rgba(0,0,0,.4);
    }
  }
  [data-theme="dark"] {
    --c-bg: #0f1117;
    --c-bg-secondary: #1a1d2e;
    --c-bg-card: #1e2130;
    --c-text: #e5e7eb;
    --c-text-secondary: #9ca3af;
    --c-text-dim: #6b7280;
    --c-border: #2d3148;
    --c-border-hover: #3d4260;
    --c-success-bg: #0d2818;
    --c-warning-bg: #2a1f00;
    --c-danger-bg: #2d0a0a;
    --c-accent-bg: #1a1533;
    --shadow-sm: 0 1px 2px rgba(0,0,0,.2);
    --shadow-md: 0 4px 6px rgba(0,0,0,.3);
    --shadow-lg: 0 10px 15px rgba(0,0,0,.4);
  }

  /* ── Body & Layout ────────────────────────────── */
  body {
    font-family: var(--font);
    background: var(--c-bg);
    color: var(--c-text);
    line-height: 1.6;
    min-height: 100vh;
  }
  .container { max-width: 1400px; margin: 0 auto; padding: var(--sp-6); }

  /* ── Header ───────────────────────────────────── */
  .header {
    position: sticky; top: 0; z-index: 100;
    background: var(--c-bg);
    border-bottom: 1px solid var(--c-border);
    padding: var(--sp-3) var(--sp-6);
    display: flex; align-items: center; justify-content: space-between;
    backdrop-filter: blur(8px);
  }
  .header-left { display: flex; align-items: center; gap: var(--sp-3); }
  .header h1 { font-size: 1.25rem; font-weight: 700; }
  .header-right { display: flex; align-items: center; gap: var(--sp-3); }
  .header .hint {
    font-size: 0.75rem; color: var(--c-text-dim);
    font-family: var(--font-mono);
  }

  /* ── Theme Toggle ─────────────────────────────── */
  .theme-toggle {
    background: var(--c-bg-secondary); border: 1px solid var(--c-border);
    border-radius: var(--r-md); padding: var(--sp-1) var(--sp-2);
    cursor: pointer; font-size: 1rem; line-height: 1;
    transition: border-color var(--t-fast) var(--ease);
  }
  .theme-toggle:hover { border-color: var(--c-border-hover); }
  .theme-toggle:focus-visible { outline: 2px solid var(--c-accent); outline-offset: 2px; }

  /* ── Hero / Global Summary ────────────────────── */
  .hero {
    display: flex; align-items: center; gap: var(--sp-8);
    padding: var(--sp-8) 0;
    flex-wrap: wrap;
  }
  .hero-score { position: relative; flex-shrink: 0; }
  .hero-score svg { width: 140px; height: 140px; }
  .hero-score .score-label {
    position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
    text-align: center;
  }
  .hero-score .score-value { font-size: 2rem; font-weight: 800; line-height: 1; }
  .hero-score .score-grade { font-size: 0.875rem; color: var(--c-text-secondary); }

  .hero-stats {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: var(--sp-4); flex: 1;
  }
  .stat-card {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-lg); padding: var(--sp-4);
    text-align: center;
  }
  .stat-card .stat-value { font-size: 1.75rem; font-weight: 700; }
  .stat-card .stat-label { font-size: 0.75rem; color: var(--c-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; }

  /* ── Persona Strip ────────────────────────────── */
  .persona-strip {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-lg); padding: var(--sp-4) var(--sp-6);
    display: flex; align-items: center; gap: var(--sp-6);
    flex-wrap: wrap; margin-bottom: var(--sp-6);
  }
  .persona-badge {
    background: var(--c-accent-bg); color: var(--c-accent);
    padding: var(--sp-1) var(--sp-3); border-radius: var(--r-md);
    font-weight: 600; font-size: 0.875rem;
  }
  .axes-display { display: flex; gap: var(--sp-4); flex-wrap: wrap; }
  .axis-item { font-size: 0.8rem; }
  .axis-label { color: var(--c-text-secondary); }
  .axis-value { font-weight: 600; margin-left: var(--sp-1); }
  .persona-meta { display: flex; gap: var(--sp-4); font-size: 0.8rem; color: var(--c-text-secondary); margin-left: auto; }

  /* ── Score Ring (SVG) ─────────────────────────── */
  .score-ring-bg { fill: none; stroke: var(--c-border); stroke-width: 8; }
  .score-ring-fill {
    fill: none; stroke-width: 8; stroke-linecap: round;
    transform: rotate(-90deg); transform-origin: center;
    transition: stroke-dasharray var(--t-slow) var(--ease);
  }
  .score-a { stroke: var(--c-success); }
  .score-b { stroke: var(--c-success); opacity: 0.8; }
  .score-c { stroke: var(--c-warning); }
  .score-d { stroke: var(--c-warning); opacity: 0.8; }
  .score-f { stroke: var(--c-danger); }

  /* ── Recommendations ──────────────────────────── */
  .recommendations {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-lg); margin-bottom: var(--sp-6);
    overflow: hidden;
  }
  .recommendations-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: var(--sp-4) var(--sp-6); cursor: pointer;
    border-bottom: 1px solid var(--c-border);
    user-select: none;
  }
  .recommendations-header h2 { font-size: 1rem; font-weight: 600; }
  .severity-bar { display: flex; gap: var(--sp-2); }
  .severity-badge {
    padding: var(--sp-1) var(--sp-2); border-radius: var(--r-sm);
    font-size: 0.75rem; font-weight: 600;
  }
  .severity-high { background: var(--c-danger-bg); color: var(--c-danger); }
  .severity-medium { background: var(--c-warning-bg); color: var(--c-warning); }
  .severity-low { background: var(--c-success-bg); color: var(--c-success); }
  .recommendations-body { padding: var(--sp-4) var(--sp-6); }
  .recommendations-body.collapsed { display: none; }
  .rec-card {
    display: flex; align-items: flex-start; gap: var(--sp-3);
    padding: var(--sp-3) 0; border-bottom: 1px solid var(--c-border);
  }
  .rec-card:last-child { border-bottom: none; }
  .rec-icon { flex-shrink: 0; width: 20px; text-align: center; }
  .rec-content { flex: 1; }
  .rec-title { font-weight: 600; font-size: 0.875rem; }
  .rec-desc { font-size: 0.8rem; color: var(--c-text-secondary); margin-top: var(--sp-1); }
  .rec-command {
    font-family: var(--font-mono); font-size: 0.75rem;
    background: var(--c-bg-secondary); padding: var(--sp-1) var(--sp-2);
    border-radius: var(--r-sm); margin-top: var(--sp-1);
    display: inline-flex; align-items: center; gap: var(--sp-2);
    cursor: pointer; border: 1px solid var(--c-border);
    transition: border-color var(--t-fast) var(--ease);
  }
  .rec-command:hover { border-color: var(--c-border-hover); }
  .copy-all-btn {
    background: var(--c-accent); color: white; border: none;
    padding: var(--sp-2) var(--sp-4); border-radius: var(--r-md);
    font-size: 0.8rem; font-weight: 600; cursor: pointer;
    margin-top: var(--sp-4);
    transition: opacity var(--t-fast) var(--ease);
  }
  .copy-all-btn:hover { opacity: 0.9; }
  .copy-all-btn:focus-visible { outline: 2px solid var(--c-accent); outline-offset: 2px; }

  /* ── Repo Toolbar ─────────────────────────────── */
  .repo-toolbar {
    display: flex; align-items: center; gap: var(--sp-3);
    margin-bottom: var(--sp-4); flex-wrap: wrap;
  }
  .search-input {
    flex: 1; min-width: 200px;
    padding: var(--sp-2) var(--sp-3);
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-md); color: var(--c-text);
    font-family: var(--font); font-size: 0.875rem;
    transition: border-color var(--t-fast) var(--ease);
  }
  .search-input:focus { border-color: var(--c-accent); outline: none; }
  .search-input::placeholder { color: var(--c-text-dim); }

  .toolbar-select {
    padding: var(--sp-2) var(--sp-3);
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-md); color: var(--c-text);
    font-size: 0.8rem; cursor: pointer;
  }
  .toolbar-btn {
    padding: var(--sp-2) var(--sp-3);
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-md); cursor: pointer; font-size: 0.8rem;
    color: var(--c-text);
    transition: border-color var(--t-fast) var(--ease);
  }
  .toolbar-btn:hover { border-color: var(--c-border-hover); }
  .toolbar-btn.active { border-color: var(--c-accent); color: var(--c-accent); }
  .toolbar-btn:focus-visible { outline: 2px solid var(--c-accent); outline-offset: 2px; }

  /* ── Repo Grid ────────────────────────────────── */
  .repo-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--sp-4);
  }
  .repo-card {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-lg); padding: var(--sp-4);
    cursor: pointer; transition: all var(--t-fast) var(--ease);
    scroll-margin-top: 80px;
  }
  .repo-card:hover { border-color: var(--c-border-hover); box-shadow: var(--shadow-md); }
  .repo-card:focus-visible { outline: 2px solid var(--c-accent); outline-offset: 2px; }
  .repo-card.active { border-color: var(--c-accent); }
  .repo-card-header { display: flex; align-items: center; gap: var(--sp-3); margin-bottom: var(--sp-3); }
  .repo-mini-score { position: relative; flex-shrink: 0; }
  .repo-mini-score svg { width: 44px; height: 44px; }
  .repo-mini-score .mini-label {
    position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
    font-size: 0.7rem; font-weight: 700;
  }
  .repo-name { font-weight: 600; font-size: 0.95rem; word-break: break-all; }
  .repo-path { font-size: 0.7rem; color: var(--c-text-dim); font-family: var(--font-mono); }
  .repo-indicators { display: flex; gap: var(--sp-2); flex-wrap: wrap; margin-top: var(--sp-2); }
  .indicator {
    font-size: 0.7rem; padding: 2px var(--sp-2); border-radius: var(--r-sm);
    background: var(--c-bg-secondary); color: var(--c-text-secondary);
  }
  .indicator.present { background: var(--c-success-bg); color: var(--c-success); }
  .indicator.missing { background: var(--c-danger-bg); color: var(--c-danger); }

  /* ── Repo Detail (expanded) ───────────────────── */
  .repo-detail { display: none; margin-top: var(--sp-4); padding-top: var(--sp-4); border-top: 1px solid var(--c-border); }
  .repo-card.expanded .repo-detail { display: block; }
  .dimension-bars { margin-bottom: var(--sp-3); }
  .dim-row { display: flex; align-items: center; gap: var(--sp-2); margin-bottom: var(--sp-1); font-size: 0.8rem; }
  .dim-label { width: 80px; color: var(--c-text-secondary); flex-shrink: 0; }
  .dim-bar { flex: 1; height: 6px; background: var(--c-bg-secondary); border-radius: 3px; overflow: hidden; }
  .dim-bar-fill { height: 100%; border-radius: 3px; transition: width var(--t-med) var(--ease); }
  .dim-value { width: 30px; text-align: right; font-weight: 600; font-size: 0.75rem; }

  /* ── Footer ───────────────────────────────────── */
  .footer {
    text-align: center; padding: var(--sp-8) 0 var(--sp-4);
    font-size: 0.75rem; color: var(--c-text-dim);
  }
  .footer a { color: var(--c-accent); text-decoration: none; }
  .footer a:hover { text-decoration: underline; }
  .footer .kbd {
    display: inline-block; padding: 1px 5px;
    background: var(--c-bg-secondary); border: 1px solid var(--c-border);
    border-radius: var(--r-sm); font-family: var(--font-mono);
    font-size: 0.7rem;
  }

  /* ── Help Modal ───────────────────────────────── */
  .modal-overlay {
    display: none; position: fixed; inset: 0; z-index: 200;
    background: rgba(0,0,0,.5); backdrop-filter: blur(2px);
    align-items: center; justify-content: center;
  }
  .modal-overlay.visible { display: flex; }
  .modal {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-xl); padding: var(--sp-6);
    max-width: 480px; width: 90%; max-height: 80vh; overflow-y: auto;
    box-shadow: var(--shadow-lg);
  }
  .modal h2 { font-size: 1.1rem; margin-bottom: var(--sp-4); }
  .shortcut-row { display: flex; justify-content: space-between; padding: var(--sp-1) 0; font-size: 0.85rem; }
  .shortcut-key { font-family: var(--font-mono); font-weight: 600; }

  /* ── Toast ────────────────────────────────────── */
  .toast-container {
    position: fixed; bottom: var(--sp-6); right: var(--sp-6); z-index: 300;
    display: flex; flex-direction: column; gap: var(--sp-2);
  }
  .toast {
    background: var(--c-bg-card); border: 1px solid var(--c-border);
    border-radius: var(--r-md); padding: var(--sp-2) var(--sp-4);
    box-shadow: var(--shadow-md); font-size: 0.8rem;
    animation: toast-in var(--t-med) var(--ease);
  }
  .toast.fade-out { animation: toast-out var(--t-med) var(--ease) forwards; }
  @keyframes toast-in { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
  @keyframes toast-out { from { opacity: 1; } to { opacity: 0; transform: translateY(-10px); } }

  /* ── Focus Mode ───────────────────────────────── */
  .focus-mode .repo-card.healthy { display: none; }
  .focus-indicator {
    display: none; padding: var(--sp-2) var(--sp-4);
    background: var(--c-warning-bg); color: var(--c-warning);
    border-radius: var(--r-md); font-size: 0.8rem; font-weight: 600;
  }
  .focus-mode .focus-indicator { display: inline-block; }

  /* ── Responsive ───────────────────────────────── */
  @media (max-width: 768px) {
    .hero { flex-direction: column; align-items: flex-start; }
    .hero-stats { grid-template-columns: repeat(2, 1fr); }
    .persona-strip { flex-direction: column; align-items: flex-start; }
    .persona-meta { margin-left: 0; }
    .repo-grid { grid-template-columns: 1fr; }
  }
  @media (min-width: 1200px) {
    .repo-grid { grid-template-columns: repeat(3, 1fr); }
  }
  @media (min-width: 1600px) {
    .repo-grid { grid-template-columns: repeat(4, 1fr); }
  }

  /* ── Print ────────────────────────────────────── */
  @media print {
    :root { --c-bg: #fff !important; --c-text: #000 !important; }
    .header, .theme-toggle, .toolbar-btn, .copy-all-btn, .toast-container,
    .modal-overlay, .focus-indicator { display: none !important; }
    .repo-detail { display: block !important; }
    .recommendations-body { display: block !important; }
    .repo-grid { display: block; }
    .repo-card { break-inside: avoid; margin-bottom: var(--sp-4); }
  }

  /* ── Reduced Motion ───────────────────────────── */
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
  }

  /* ── ARIA & Accessibility ─────────────────────── */
  .sr-only {
    position: absolute; width: 1px; height: 1px;
    padding: 0; margin: -1px; overflow: hidden;
    clip: rect(0,0,0,0); white-space: nowrap; border: 0;
  }
  :focus-visible { outline: 2px solid var(--c-accent); outline-offset: 2px; }
  .no-results { text-align: center; padding: var(--sp-12) 0; color: var(--c-text-dim); }
</style>
STYLES
}

# ── HTML: Document Head ──────────────────────────────────────

_emit_head() {
  cat <<'HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Forge Dashboard</title>
  <meta name="description" content="Claude Code Forge configuration dashboard">
HEAD
  _emit_styles
  echo '</head>'
}

# ── HTML: Header ─────────────────────────────────────────────

_emit_header() {
  cat <<'HEADER'
<header class="header" role="banner">
  <div class="header-left">
    <h1>Forge Dashboard</h1>
  </div>
  <div class="header-right">
    <span class="hint" aria-hidden="true">/ search &middot; ? help</span>
    <button class="theme-toggle" id="themeToggle" aria-label="Toggle theme" title="Toggle theme (t)">
      <span class="theme-icon" aria-hidden="true"></span>
    </button>
  </div>
</header>
HEADER
}

# ── HTML: Hero Section ───────────────────────────────────────

_emit_hero() {
  cat <<'HERO'
<section class="hero" aria-label="Global effectiveness summary">
  <div class="hero-score" id="heroScore"></div>
  <div class="hero-stats" id="heroStats"></div>
</section>
HERO
}

# ── HTML: Persona Strip ──────────────────────────────────────

_emit_persona_strip() {
  cat <<'PERSONA'
<section class="persona-strip" id="personaStrip" aria-label="Active persona configuration"></section>
PERSONA
}

# ── HTML: Recommendations ────────────────────────────────────

_emit_recommendations() {
  cat <<'RECS'
<section class="recommendations" id="recommendations" aria-label="Recommendations">
  <div class="recommendations-header" id="recsToggle" role="button" tabindex="0" aria-expanded="true">
    <h2>Recommendations</h2>
    <div class="severity-bar" id="severityBar"></div>
  </div>
  <div class="recommendations-body" id="recsBody"></div>
</section>
RECS
}

# ── HTML: Repo Toolbar ───────────────────────────────────────

_emit_repo_toolbar() {
  cat <<'TOOLBAR'
<div class="repo-toolbar" role="toolbar" aria-label="Repository filters">
  <input type="search" class="search-input" id="searchInput"
    placeholder="Search repos... (/ to focus)" aria-label="Search repositories">
  <select class="toolbar-select" id="sortSelect" aria-label="Sort by">
    <option value="score-desc">Score (high first)</option>
    <option value="score-asc">Score (low first)</option>
    <option value="name-asc">Name (A-Z)</option>
    <option value="name-desc">Name (Z-A)</option>
  </select>
  <select class="toolbar-select" id="filterSelect" aria-label="Filter by grade">
    <option value="all">All grades</option>
    <option value="A">A only</option>
    <option value="B">B only</option>
    <option value="C">C only</option>
    <option value="D">D only</option>
    <option value="F">F only</option>
  </select>
  <button class="toolbar-btn" id="focusToggle" aria-pressed="false" title="Focus mode (f)">Focus</button>
  <span class="focus-indicator" role="status">Focus mode: showing repos needing attention</span>
</div>
TOOLBAR
}

# ── HTML: Repo Grid ──────────────────────────────────────────

_emit_repo_grid() {
  cat <<'GRID'
<main id="repoGrid" class="repo-grid" role="main" aria-label="Repository cards">
</main>
<div class="no-results" id="noResults" style="display:none" role="status">
  No repositories match your search.
</div>
GRID
}

# ── HTML: Footer ─────────────────────────────────────────────

_emit_footer() {
  cat <<'FOOTER'
<footer class="footer" role="contentinfo">
  <p id="footerInfo"></p>
  <p>Press <kbd class="kbd">?</kbd> for keyboard shortcuts</p>
</footer>
FOOTER
}

# ── HTML: Help Modal ─────────────────────────────────────────

_emit_help_modal() {
  cat <<'MODAL'
<div class="modal-overlay" id="helpModal" role="dialog" aria-modal="true" aria-label="Keyboard shortcuts">
  <div class="modal">
    <h2>Keyboard Shortcuts</h2>
    <div class="shortcut-row"><span>Navigate repos</span><span class="shortcut-key">j / k</span></div>
    <div class="shortcut-row"><span>Expand/collapse repo</span><span class="shortcut-key">Enter</span></div>
    <div class="shortcut-row"><span>Search</span><span class="shortcut-key">/</span></div>
    <div class="shortcut-row"><span>Close / deselect</span><span class="shortcut-key">Escape</span></div>
    <div class="shortcut-row"><span>Toggle theme</span><span class="shortcut-key">t</span></div>
    <div class="shortcut-row"><span>Focus mode</span><span class="shortcut-key">f</span></div>
    <div class="shortcut-row"><span>Jump to first repo</span><span class="shortcut-key">g</span></div>
    <div class="shortcut-row"><span>This help</span><span class="shortcut-key">?</span></div>
  </div>
</div>
MODAL
}

# ── HTML: Toast Container + Live Region ──────────────────────

_emit_toast_and_live() {
  cat <<'TOAST'
<div class="toast-container" id="toastContainer" aria-live="polite"></div>
<div class="sr-only" id="liveRegion" role="status" aria-live="polite" aria-atomic="true"></div>
TOAST
}

# ── HTML: Data Injection ─────────────────────────────────────

_emit_data() {
  local json="$1"
  # Compact JSON to single line for reliable embedding and extraction
  local compact
  compact=$(echo "$json" | jq -c '.')
  printf '<script>const DATA = %s;</script>\n' "$compact"
}

# ── HTML: Application JavaScript ─────────────────────────────

_emit_script() {
  cat <<'SCRIPT'
<script>
(function() {
  'use strict';

  // ── Helpers ──────────────────────────────────
  const $ = s => document.querySelector(s);
  const $$ = s => [...document.querySelectorAll(s)];
  const announce = msg => { const r = $('#liveRegion'); if (r) { r.textContent = ''; requestAnimationFrame(() => r.textContent = msg); } };

  function toast(msg) {
    const c = $('#toastContainer');
    const t = document.createElement('div');
    t.className = 'toast'; t.textContent = msg;
    c.appendChild(t);
    setTimeout(() => { t.classList.add('fade-out'); setTimeout(() => t.remove(), 300); }, 2000);
  }

  async function copyText(text) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
      } else {
        const ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
      }
      toast('Copied to clipboard');
    } catch { toast('Copy failed'); }
  }

  // ── Score Ring SVG ───────────────────────────
  function scoreRing(score, grade, size) {
    const r = size * 0.38;
    const circ = 2 * Math.PI * r;
    const offset = circ * (1 - score / 100);
    const cls = grade === 'A' ? 'score-a' : grade === 'B' ? 'score-b' : grade === 'C' ? 'score-c' : grade === 'D' ? 'score-d' : 'score-f';
    return '<svg viewBox="0 0 ' + size + ' ' + size + '" width="' + size + '" height="' + size + '" role="img" aria-label="Score: ' + score + ' (' + grade + ')">' +
      '<circle class="score-ring-bg" cx="' + size/2 + '" cy="' + size/2 + '" r="' + r + '"/>' +
      '<circle class="score-ring-fill ' + cls + '" cx="' + size/2 + '" cy="' + size/2 + '" r="' + r + '" stroke-dasharray="' + circ + '" stroke-dashoffset="' + offset + '"/>' +
      '</svg>';
  }

  function dimBarColor(score) {
    if (score >= 80) return 'var(--c-success)';
    if (score >= 60) return 'var(--c-warning)';
    return 'var(--c-danger)';
  }

  // ── Render: Hero ─────────────────────────────
  function renderHero() {
    const g = DATA.global_score;
    const el = $('#heroScore');
    el.innerHTML = '<div class="hero-score">' + scoreRing(g.total, g.grade, 140) +
      '<div class="score-label"><div class="score-value">' + g.total + '</div><div class="score-grade">' + g.grade + '</div></div></div>';

    const repos = DATA.repos || [];
    const needsAttention = repos.filter(r => r.score && r.score.total < 70).length;
    const hooksCount = (DATA.global && DATA.global.hooks) ? DATA.global.hooks.length : 0;
    const version = (DATA.global && DATA.global.install) ? DATA.global.install.forge_version : '?';

    $('#heroStats').innerHTML =
      '<div class="stat-card"><div class="stat-value">' + repos.length + '</div><div class="stat-label">Repos Tracked</div></div>' +
      '<div class="stat-card"><div class="stat-value">' + needsAttention + '</div><div class="stat-label">Need Attention</div></div>' +
      '<div class="stat-card"><div class="stat-value">' + hooksCount + '</div><div class="stat-label">Hooks Active</div></div>' +
      '<div class="stat-card"><div class="stat-value">v' + version + '</div><div class="stat-label">Forge Version</div></div>';
  }

  // ── Render: Persona Strip ────────────────────
  function renderPersona() {
    const p = DATA.global ? DATA.global.persona : {};
    const pl = DATA.global ? DATA.global.plugins : {};
    const ru = DATA.global ? DATA.global.rules : {};

    let html = '<span class="persona-badge">' + (p.label || 'Unknown') + '</span>';
    html += '<div class="axes-display">';
    const axes = p.axes || {};
    for (const [k, v] of Object.entries(axes)) {
      html += '<span class="axis-item"><span class="axis-label">' + k + ':</span><span class="axis-value">' + v + '</span></span>';
    }
    html += '</div>';
    html += '<div class="persona-meta">';
    html += '<span>Plugins: ' + (pl.group || '?') + ' (' + (pl.count || 0) + ')</span>';
    html += '<span>Rules: ' + (ru.count || 0) + '</span>';
    html += '</div>';

    $('#personaStrip').innerHTML = html;
  }

  // ── Recommendations Engine ───────────────────
  function generateRecommendations() {
    const recs = [];
    const g = DATA.global || {};
    const gs = DATA.global_score || {};

    // Global recommendations
    if (!g.claude_md || !g.claude_md.exists) {
      recs.push({ severity: 'high', title: 'Missing global CLAUDE.md', desc: 'Install forge to generate your global configuration.', command: 'forge install' });
    }
    if (gs.dimensions && gs.dimensions.hook_coverage && gs.dimensions.hook_coverage.score < 50) {
      recs.push({ severity: 'high', title: 'Low hook coverage', desc: 'Security and workflow hooks are not fully configured.', command: 'forge install --reconfigure' });
    }
    if (gs.dimensions && gs.dimensions.rule_coverage && gs.dimensions.rule_coverage.score < 60) {
      recs.push({ severity: 'medium', title: 'Missing rules', desc: 'Some expected rule files are not installed.', command: 'forge update' });
    }
    if (gs.dimensions && gs.dimensions.plugin_alignment && gs.dimensions.plugin_alignment.score < 80) {
      recs.push({ severity: 'medium', title: 'Plugin mismatch', desc: 'Not all recommended plugins for your persona are enabled.', command: 'forge install --reconfigure' });
    }
    if (gs.dimensions && gs.dimensions.freshness && gs.dimensions.freshness.score < 40) {
      recs.push({ severity: 'low', title: 'Stale configuration', desc: 'Your forge installation has not been updated recently.', command: 'forge update' });
    }

    // Per-repo recommendations
    (DATA.repos || []).forEach(r => {
      if (!r.claude_md || !r.claude_md.exists) {
        recs.push({ severity: 'medium', title: r.name + ': Missing CLAUDE.md', desc: 'Initialize project-level forge config.', command: 'cd ' + r.path + ' && forge init' });
      }
      if (r.score && r.score.dimensions && r.score.dimensions.doc_chain && r.score.dimensions.doc_chain.score === 0) {
        recs.push({ severity: 'low', title: r.name + ': No document chain', desc: 'Add PROJECT.md, REQUIREMENTS.md, or ROADMAP.md for multi-session work.', command: 'cd ' + r.path + ' && forge init --docs' });
      }
    });

    return recs;
  }

  function renderRecommendations() {
    const recs = generateRecommendations();
    const section = $('#recommendations');
    if (recs.length === 0) { section.style.display = 'none'; return; }

    const high = recs.filter(r => r.severity === 'high').length;
    const med = recs.filter(r => r.severity === 'medium').length;
    const low = recs.filter(r => r.severity === 'low').length;

    let barHtml = '';
    if (high) barHtml += '<span class="severity-badge severity-high">' + high + ' high</span>';
    if (med) barHtml += '<span class="severity-badge severity-medium">' + med + ' medium</span>';
    if (low) barHtml += '<span class="severity-badge severity-low">' + low + ' low</span>';
    $('#severityBar').innerHTML = barHtml;

    const icons = { high: '!', medium: '~', low: '-' };
    let bodyHtml = '';
    recs.sort((a, b) => { const o = { high: 0, medium: 1, low: 2 }; return o[a.severity] - o[b.severity]; });
    recs.forEach(r => {
      bodyHtml += '<div class="rec-card"><div class="rec-icon severity-' + r.severity + '">' + icons[r.severity] + '</div>' +
        '<div class="rec-content"><div class="rec-title">' + r.title + '</div>' +
        '<div class="rec-desc">' + r.desc + '</div>';
      if (r.command) {
        bodyHtml += '<code class="rec-command" data-copy="' + r.command.replace(/"/g, '&quot;') + '" tabindex="0" role="button" aria-label="Copy command: ' + r.command.replace(/"/g, '&quot;') + '">' + r.command + '</code>';
      }
      bodyHtml += '</div></div>';
    });

    const commands = recs.filter(r => r.command).map(r => r.command);
    if (commands.length > 1) {
      bodyHtml += '<button class="copy-all-btn" id="copyAllBtn">Copy all commands (' + commands.length + ')</button>';
    }
    $('#recsBody').innerHTML = bodyHtml;

    // Auto-expand if high severity
    if (high > 0) { $('#recsBody').classList.remove('collapsed'); }

    // Bind copy handlers
    $$('.rec-command').forEach(el => {
      el.addEventListener('click', () => copyText(el.dataset.copy));
      el.addEventListener('keydown', e => { if (e.key === 'Enter') copyText(el.dataset.copy); });
    });

    const copyAllBtn = $('#copyAllBtn');
    if (copyAllBtn) {
      copyAllBtn.addEventListener('click', () => copyText(commands.join('\n')));
    }
  }

  // ── Render: Repo Cards ───────────────────────
  let currentFocusIndex = -1;

  function renderRepoCards() {
    const grid = $('#repoGrid');
    const repos = DATA.repos || [];
    if (repos.length === 0) {
      grid.innerHTML = '<div class="no-results">No repositories found. Configure scan path: <code>forge config set dashboard.scan_path ~/repos</code></div>';
      return;
    }

    let html = '';
    repos.forEach((r, i) => {
      const s = r.score || { total: 0, grade: 'F', dimensions: {} };
      const healthy = s.total >= 70;
      const id = 'repo-' + r.name.replace(/[^a-zA-Z0-9-]/g, '-');

      html += '<article class="repo-card' + (healthy ? ' healthy' : '') + '" id="' + id + '" data-index="' + i + '" tabindex="0" role="article" aria-label="' + r.name + ' - score ' + s.total + '">';
      html += '<div class="repo-card-header">';
      html += '<div class="repo-mini-score">' + scoreRing(s.total, s.grade, 44) + '<span class="mini-label">' + s.grade + '</span></div>';
      html += '<div><div class="repo-name">' + r.name + '</div><div class="repo-path">' + r.path + '</div></div>';
      html += '</div>';

      // Indicators
      html += '<div class="repo-indicators">';
      html += '<span class="indicator ' + (r.claude_md && r.claude_md.exists ? 'present' : 'missing') + '">CLAUDE.md</span>';
      html += '<span class="indicator ' + (r.doc_chain && r.doc_chain.project_md ? 'present' : '') + '">PROJECT</span>';
      html += '<span class="indicator ' + (r.doc_chain && r.doc_chain.requirements_md ? 'present' : '') + '">REQS</span>';
      html += '<span class="indicator ' + (r.doc_chain && r.doc_chain.roadmap_md ? 'present' : '') + '">ROADMAP</span>';
      if (r.rules && r.rules.count > 0) html += '<span class="indicator present">' + r.rules.count + ' rules</span>';
      html += '</div>';

      // Detail (hidden until expanded)
      html += '<div class="repo-detail">';
      html += '<div class="dimension-bars">';
      if (s.dimensions) {
        for (const [k, d] of Object.entries(s.dimensions)) {
          const label = k.replace(/_/g, ' ');
          html += '<div class="dim-row"><span class="dim-label">' + label + '</span>' +
            '<div class="dim-bar"><div class="dim-bar-fill" style="width:' + d.score + '%;background:' + dimBarColor(d.score) + '"></div></div>' +
            '<span class="dim-value">' + d.score + '</span></div>';
        }
      }
      html += '</div>';

      // Rules list
      if (r.rules && r.rules.files && r.rules.files.length) {
        html += '<div style="font-size:0.8rem;color:var(--c-text-secondary);margin-bottom:var(--sp-2)"><strong>Rules:</strong> ' + r.rules.files.join(', ') + '</div>';
      }
      // Git info
      if (r.git && r.git.is_repo && r.git.branch) {
        html += '<div style="font-size:0.8rem;color:var(--c-text-secondary)"><strong>Branch:</strong> ' + r.git.branch + '</div>';
      }
      html += '</div></article>';
    });

    grid.innerHTML = html;

    // Bind expand/collapse
    $$('.repo-card').forEach(card => {
      card.addEventListener('click', () => toggleCard(card));
      card.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); toggleCard(card); } });
    });

    // Hash-based deep link
    if (location.hash) {
      const target = $(location.hash);
      if (target && target.classList.contains('repo-card')) {
        toggleCard(target);
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    }
  }

  function toggleCard(card) {
    const wasExpanded = card.classList.contains('expanded');
    $$('.repo-card.expanded').forEach(c => c.classList.remove('expanded', 'active'));
    if (!wasExpanded) {
      card.classList.add('expanded', 'active');
      history.replaceState(null, '', '#' + card.id);
    } else {
      history.replaceState(null, '', location.pathname);
    }
  }

  // ── Search & Filter ──────────────────────────
  function applyFilters() {
    const query = $('#searchInput').value.toLowerCase();
    const gradeFilter = $('#filterSelect').value;
    const cards = $$('.repo-card');
    let visible = 0;

    cards.forEach(card => {
      const i = parseInt(card.dataset.index);
      const r = DATA.repos[i];
      const matchesSearch = !query || r.name.toLowerCase().includes(query) || r.path.toLowerCase().includes(query);
      const matchesGrade = gradeFilter === 'all' || (r.score && r.score.grade === gradeFilter);
      const show = matchesSearch && matchesGrade;
      card.style.display = show ? '' : 'none';
      if (show) visible++;
    });

    $('#noResults').style.display = visible === 0 ? '' : 'none';
    announce(visible + ' repositories shown');
  }

  function applySorting() {
    const sort = $('#sortSelect').value;
    const repos = DATA.repos || [];
    const grid = $('#repoGrid');

    const cards = $$('.repo-card');
    const sorted = cards.sort((a, b) => {
      const ra = repos[parseInt(a.dataset.index)];
      const rb = repos[parseInt(b.dataset.index)];
      switch (sort) {
        case 'score-desc': return (rb.score?.total || 0) - (ra.score?.total || 0);
        case 'score-asc': return (ra.score?.total || 0) - (rb.score?.total || 0);
        case 'name-asc': return ra.name.localeCompare(rb.name);
        case 'name-desc': return rb.name.localeCompare(ra.name);
        default: return 0;
      }
    });

    sorted.forEach(card => grid.appendChild(card));
  }

  // ── Theme ────────────────────────────────────
  function initTheme() {
    const saved = localStorage.getItem('forge-dashboard-theme');
    if (saved) document.documentElement.setAttribute('data-theme', saved);
    updateThemeIcon();
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute('data-theme');
    const isDark = current === 'dark' || (!current && window.matchMedia('(prefers-color-scheme: dark)').matches);
    const next = isDark ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('forge-dashboard-theme', next);
    updateThemeIcon();
    announce('Theme: ' + next);
  }

  function updateThemeIcon() {
    const el = $('.theme-icon');
    if (!el) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
      (!document.documentElement.getAttribute('data-theme') && window.matchMedia('(prefers-color-scheme: dark)').matches);
    el.textContent = isDark ? '\u2600' : '\u263D';
  }

  // ── Keyboard Navigation ──────────────────────
  function initKeyboard() {
    document.addEventListener('keydown', e => {
      // Ignore when typing in inputs
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') {
        if (e.key === 'Escape') { e.target.blur(); e.preventDefault(); }
        return;
      }

      const modal = $('#helpModal');
      if (modal.classList.contains('visible')) {
        if (e.key === 'Escape' || e.key === '?') { modal.classList.remove('visible'); e.preventDefault(); }
        return;
      }

      switch (e.key) {
        case 'j': navigateCards(1); e.preventDefault(); break;
        case 'k': navigateCards(-1); e.preventDefault(); break;
        case '/': $('#searchInput').focus(); e.preventDefault(); break;
        case '?': modal.classList.add('visible'); e.preventDefault(); break;
        case 't': toggleTheme(); e.preventDefault(); break;
        case 'f': toggleFocusMode(); e.preventDefault(); break;
        case 'g': navigateCards(0, true); e.preventDefault(); break;
        case 'Escape': deselectAll(); e.preventDefault(); break;
        case 'Enter': {
          const active = $$('.repo-card')[currentFocusIndex];
          if (active) { toggleCard(active); e.preventDefault(); }
          break;
        }
      }
    });
  }

  function navigateCards(dir, jumpToFirst) {
    const cards = $$('.repo-card').filter(c => c.style.display !== 'none');
    if (!cards.length) return;
    if (jumpToFirst) { currentFocusIndex = 0; }
    else { currentFocusIndex = Math.max(0, Math.min(cards.length - 1, currentFocusIndex + dir)); }
    cards[currentFocusIndex].focus();
    cards[currentFocusIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  function deselectAll() {
    $$('.repo-card.expanded').forEach(c => c.classList.remove('expanded', 'active'));
    currentFocusIndex = -1;
    history.replaceState(null, '', location.pathname);
  }

  // ── Focus Mode ───────────────────────────────
  function toggleFocusMode() {
    const body = document.body;
    const active = body.classList.toggle('focus-mode');
    $('#focusToggle').setAttribute('aria-pressed', active);
    $('#focusToggle').classList.toggle('active', active);
    announce(active ? 'Focus mode: showing repos needing attention' : 'Focus mode off');
  }

  // ── Recommendations Toggle ───────────────────
  function initRecsToggle() {
    const toggle = $('#recsToggle');
    const body = $('#recsBody');
    if (!toggle || !body) return;
    toggle.addEventListener('click', () => {
      const collapsed = body.classList.toggle('collapsed');
      toggle.setAttribute('aria-expanded', !collapsed);
    });
    toggle.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle.click(); }
    });
  }

  // ── Footer ───────────────────────────────────
  function renderFooter() {
    const ts = DATA.generated_at || 'unknown';
    const version = (DATA.global && DATA.global.install) ? DATA.global.install.forge_version : '?';
    $('#footerInfo').textContent = 'Generated ' + ts + ' \u00B7 forge v' + version;
  }

  // ── Init ─────────────────────────────────────
  function init() {
    initTheme();
    renderHero();
    renderPersona();
    renderRecommendations();
    renderRepoCards();
    renderFooter();
    initRecsToggle();
    initKeyboard();

    $('#searchInput').addEventListener('input', applyFilters);
    $('#filterSelect').addEventListener('change', applyFilters);
    $('#sortSelect').addEventListener('change', applySorting);
    $('#themeToggle').addEventListener('click', toggleTheme);
    $('#focusToggle').addEventListener('click', toggleFocusMode);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
</script>
SCRIPT
}

# ── Public API ───────────────────────────────────────────────

# Generate complete dashboard HTML
# Args: $1 = JSON data blob, $2 = output file path
generate_dashboard() {
  local json="$1"
  local output="$2"

  mkdir -p "$(dirname "$output")"

  {
    _emit_head
    echo '<body>'
    _emit_header
    echo '<div class="container">'
    _emit_hero
    _emit_persona_strip
    _emit_recommendations
    _emit_repo_toolbar
    _emit_repo_grid
    echo '</div>'
    _emit_footer
    _emit_help_modal
    _emit_toast_and_live
    _emit_data "$json"
    _emit_script
    echo '</body></html>'
  } > "$output"
}
