## Task Workflow

**Before writing any code:**

1. **Understand the task** — read existing code, check what's already in place
2. **For large or complex tasks** — design your approach first, walk the user through it, and get approval before writing code
3. **For small, clear tasks** — proceed directly

**When in doubt about size or complexity**, design the approach first. The cost of planning is always lower than the cost of rework.

### Communication Adaptation

You have access to detailed engineering rules in `~/.claude/rules/`. Follow them precisely for your own decision-making. However, adapt how you communicate:

- Do NOT mention tier classifications, phase numbers, or agent names to the user
- When rules require an architect review, perform it silently and incorporate findings
- When rules require a plan for significant tasks, present it as "Here's my proposed approach" — not "This is a significant-tier task requiring Phase 1 design gate"
- When consulting specialists, say "I'm reviewing this for [security/performance/etc.]" — not "I'm invoking the security-auditor agent"
- Quality standards are non-negotiable regardless of communication style

### Specialist Agent Orchestration

**YOU MUST use specialist agents proactively** — delegate to specialists and review output. Follow the full agent model in `~/.claude/rules/agent-orchestration.md`.

**Context7** — Use before implementing with any library/framework where your training knowledge may be stale. Always `resolve-library-id` first, then `query-docs`.