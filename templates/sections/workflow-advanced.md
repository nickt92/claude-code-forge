## Task Workflow — READ THIS BEFORE EVERY TASK

**IMPORTANT: Before writing ANY code, you MUST follow this decision gate:**

1. **Classify the task** using the 3-tier model (see `~/.claude/rules/agent-orchestration.md`):
   - **Trivial** — single-file, clear requirements, established pattern
   - **Moderate** — multi-file but well-understood domain (new endpoint, schema change, new component)
   - **Significant** — new service, auth changes, architectural decisions, multi-system, ambiguous scope
2. **If SIGNIFICANT — you MUST, in this exact order:**
   a. Use the `EnterPlanMode` tool FIRST — do not explore or read code until you are in plan mode
   b. Explore the codebase and design the approach (while in plan mode)
   c. **Invoke** the appropriate domain architect **via the Agent tool** (e.g., `Agent: backend-development:backend-architect`). You MUST actually invoke the agent — do NOT substitute your own reasoning as an architect review.
   d. Present the plan to the user and get explicit approval
   e. Use `ExitPlanMode` and ONLY THEN begin implementation
3. **If MODERATE** — proceed directly. Domain architect reviews implementation in Phase 3, plus code reviewer.
4. **If TRIVIAL** — proceed directly, code reviewer only before committing.

**NEVER skip from exploration to implementation on significant tasks.** The gap between "I understand the code" and "I'm writing code" is exactly where the plan and architect review MUST happen.

**Ambiguous requirements** — ask clarifying questions. NEVER guess at business requirements, user-facing copy, deployment targets, or third-party selections.

### Specialist Agent Orchestration

**IMPORTANT: YOU MUST use specialist agents proactively via the Skill tool** — delegate to specialists and review output, mirroring a real engineering org.

**Mandatory gates (tier-dependent — see `~/.claude/rules/agent-orchestration.md` for full model):**
1. **Domain architect** — route by task domain (graphql-architect, database-architect, backend-architect, frontend-developer, cloud-architect, or architect-review for cross-cutting). Required for significant tasks (Phase 1) and moderate+ tasks (Phase 3 review).
2. `comprehensive-review:code-reviewer` — run LAST before every commit (quality gate, all tiers)
3. `comprehensive-review:security-auditor` — run for any auth/authz, data handling, or API security work

**Full orchestration workflow:**
```
1. Receive task → Classify as trivial / moderate / significant
2. If significant → EnterPlanMode, explore, domain architect review, write plan, ExitPlanMode
3. Implement (consult Phase 2 specialists only for genuine complexity)
4. Phase 3 review: domain architect reviews implementation (moderate+) + code-reviewer (all tiers)
5. Security-auditor if security-relevant
```

When multiple specialists are needed and their work is independent, invoke them simultaneously. Full agent model with canonical sources in `~/.claude/rules/agent-orchestration.md`.

**Context7** — MUST use before implementing with any library/framework where your training knowledge may be stale. Always `resolve-library-id` first, then `query-docs`. See `~/.claude/rules/agent-orchestration.md` for trigger guidance and the project CLAUDE.md for the specific stack versions in use.