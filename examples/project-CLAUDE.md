# Project CLAUDE.md — Example Template

<!-- Copy this file to your project root as CLAUDE.md and customize. -->
<!-- Project-level instructions override global for project-specific concerns. -->

## Overview

Brief description of your project — what it is, what it does, who uses it.

## Architecture

<!-- Describe your project structure, service communication, and key patterns. -->
<!-- This helps Claude navigate and understand your codebase. -->

```
your-project/
├── src/           # Application source
├── tests/         # Test suites
├── docs/          # Documentation
└── scripts/       # Dev tooling
```

## Tech Stack

<!-- List specific versions — Claude uses these to decide when to check Context7 -->

| Layer | Technology | Version |
|-------|-----------|---------|
| Runtime | Node.js | 20+ |
| Framework | Express | 5.x |
| Database | PostgreSQL | 15 |
| ORM | Drizzle | latest |
| Frontend | React | 19 |
| Build | Vite | 7.x |

## Development

### Common Commands

```bash
# Install
npm install

# Dev server
npm run dev

# Tests
npm test
npm run test:coverage

# Type check
npm run check

# Database
npm run db:generate    # Generate migration
npm run db:push        # Apply migration
```

### Environment Variables

Each service has a `.env.example` with all required variables.

## Key Patterns

<!-- Document project-specific patterns that Claude should follow. -->
<!-- These override global CLAUDE.md for this project. -->

### Authentication
Describe your auth flow so Claude understands how to work with it.

### API Design
REST, GraphQL, or both? What conventions do endpoints follow?

### Component Patterns
Any project-specific component patterns, state management, or UI conventions.

## Testing

### File Locations
- Unit tests: co-located with source (e.g., `src/thing/__tests__/thing.test.ts`)
- Integration tests: `tests/integration/`
- E2E tests: `tests/e2e/`

### Project-Specific Coverage Targets
<!-- Override the global 85% baseline if needed -->
- Core business logic: 90%+
- Security modules: 100%
- UI components: 70%+

## Git Workflow

- **Main branch**: `main` (or `develop` for gitflow)
- **Feature branches**: `feat/description`
- **PR target**: `main`

## Deployment

- **Platform**: Where does this deploy?
- **Production URL**: https://your-app.com
- **CI/CD**: GitHub Actions / GitLab CI / etc.

## Common Pitfalls

<!-- Save Claude from repeating your team's mistakes -->

1. **Example pitfall** — Description of what goes wrong and how to avoid it
2. **Port conflicts** — List which ports your services use
3. **Environment gotchas** — Build-time vs runtime env vars, etc.