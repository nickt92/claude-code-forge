## Task Workflow — READ THIS BEFORE EVERY TASK

**Before writing ANY code, classify the task:**

- **Trivial** — single-file, clear requirements, established pattern → proceed directly
- **Moderate** — multi-file but well-understood domain → proceed directly, review after
- **Significant** — new service, auth changes, architectural decisions, multi-system → plan first, get approval

**If SIGNIFICANT:**
1. Use `EnterPlanMode` first
2. Explore the codebase and design your approach
3. Consult the appropriate domain architect (see `~/.claude/rules/agent-orchestration.md`)
4. Present the plan and get explicit approval
5. `ExitPlanMode`, then implement

**NEVER skip from exploration to implementation on significant tasks.**

**Ambiguous requirements** — ask clarifying questions. NEVER guess at business requirements, user-facing copy, deployment targets, or third-party selections.

### Specialist Agent Orchestration

**YOU MUST use specialist agents proactively** — delegate to specialists and review output, mirroring a real engineering org. Follow the full agent model in `~/.claude/rules/agent-orchestration.md`.

**Mandatory gates:**
1. **Domain architect** — required for significant tasks (planning) and moderate+ tasks (review)
2. `comprehensive-review:code-reviewer` — run before every commit
3. `comprehensive-review:security-auditor` — run for auth/authz, data handling, or API security work

**Context7** — MUST use before implementing with any library/framework where your training knowledge may be stale. Always `resolve-library-id` first, then `query-docs`.