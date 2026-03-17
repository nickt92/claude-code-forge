# Roadmap — Claude Code Forge

## Dashboard Feature

### Phase 1 — MVP Dashboard (in-progress)

Config visibility, repo scanning, scoring, recommendations, dark mode, keyboard nav, accessibility, responsive design, print styles.

- `forge dashboard` generates self-contained HTML at `~/.claude/dashboard/index.html`
- `forge config get/set` for persistent forge settings
- Global config overview: persona, hooks, plugins, rules
- Per-repo health: CLAUDE.md, rules, document chain
- Effectiveness scoring: weighted 0-100 with letter grades
- Recommendations panel with copy-to-clipboard commands
- Light/dark mode with OS preference detection + manual toggle
- Vim-style keyboard navigation (j/k, /, ?, t, f, g)
- Responsive grid: 1-4 columns based on viewport
- WCAG 2.1 AA accessibility, ARIA landmarks, screen reader support
- Print styles, reduced motion support
- Focus mode for repos needing attention

### Phase 2 — Security Analytics (planned)

- Security log parsing and event aggregation
- SVG sparkline charts for security events over time
- Hook effectiveness breakdown (blocks vs allows)
- Per-repo security event attribution
- Security score dimension added to effectiveness scoring

### Phase 3 — Power Features (planned)

- `forge dashboard --watch` auto-regeneration on config change
- Caching layer for faster regeneration
- Side-by-side config comparison view
- `forge dashboard --json` for scripting and CI integration

### Phase 4 — Integration (planned)

- `forge dashboard --ci` for compliance checks in CI pipelines
- Historical score tracking across dashboard generations
- Sparkline trends on repo cards
- `forge status` integration with dashboard link
