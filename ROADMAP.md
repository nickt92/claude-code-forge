# Roadmap — Claude Code Forge

## Forge Desktop — Native macOS Application

### Phase 0 — CLI Cleanup (in-progress)

Remove web UI, make JSON the default dashboard output, add `--json` to doctor and status.

- Delete `forge-server.js`, `web/`, `cmd-ui.sh`, `dashboard/generate.sh`
- `forge dashboard` outputs JSON to stdout (no HTML generation)
- `forge doctor --json` for structured diagnostic output
- `forge status --json` for structured status output
- All JSON outputs include `schema_version: 1`

### Phase 1 — Minimal Viable App (planned)

Read-only native macOS dashboard (SwiftUI) + menu bar icon.

- Swift app in `app/` directory alongside CLI
- Menu bar icon with aggregate health score
- Main window: global score, persona, repo grid with scores/grades
- Repo detail view with audit breakdown
- Settings: native folder picker for scan path
- macOS 14 (Sonoma) minimum
- Data flow: shell out to `forge` CLI, parse JSON

### Phase 2 — Actions & Setup (planned)

- Fix actions: add missing CLAUDE.md sections, init project config
- First-run setup wizard (detect forge CLI, configure scan path)
- Run `forge init` and `forge doctor` from app

### Phase 3 — Distribution & Polish (planned)

- FSEvents auto-refresh on config changes
- Background refresh timer (configurable)
- Native notifications for score degradation
- Developer ID signing + notarization
- GitHub Actions CI → .dmg → GitHub Releases
- Homebrew cask formula in `nickt/homebrew-forge` tap
