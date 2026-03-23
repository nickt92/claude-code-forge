# Agent Orchestration — 4-Phase Utilization Model

## Task Classification (3-Tier)

Before choosing agents, classify the task:

| Tier | Criteria | Design Gate | Review Gate |
|------|----------|-------------|-------------|
| **Trivial** | Single-file, clear requirements, established pattern | None | Code reviewer only |
| **Moderate** | Multi-file but well-understood domain, schema change, new endpoint/component | None (skip Phase 1) | Domain architect reviews implementation + code reviewer |
| **Significant** | New service, auth changes, architectural decisions, multi-system features, ambiguous scope | Full Phase 1 (plan + domain architect) | Domain architect reviews implementation + code reviewer |

**Default:** When unsure between moderate and significant, choose significant. The cost of an unnecessary plan is far lower than the cost of a bad architectural decision.

## Phase 1 — Design (Significant Tasks Only, Hook-Enforced)

Pick the domain architect matching the task. Multiple domains = run multiple in parallel.

| Task Domain | Domain Architect | Canonical Source |
|-------------|-----------------|------------------|
| GraphQL schema, resolvers, mutations | `graphql-architect` | `backend-development:graphql-architect` |
| Database schema, migrations, queries | `database-architect` | `database-design:database-architect` |
| REST API, service logic, middleware | `backend-architect` | `backend-development:backend-architect` |
| React/Next.js components, state, UI | `frontend-developer` | `frontend-mobile-development:frontend-developer` |
| CI/CD, infrastructure, deployment | `cloud-architect` | `cicd-automation:cloud-architect` |
| System boundaries, cross-cutting | `architect-review` | `comprehensive-review:architect-review` |
| Auth, data handling, OWASP | `security-auditor` | `comprehensive-review:security-auditor` (additive) |

**Default:** If unclear or multi-domain, use `comprehensive-review:architect-review`.

**Invocation:** You MUST invoke the domain architect as a **subagent** using the Agent tool with `subagent_type` set to the canonical source (e.g., `backend-development:backend-architect`). Summarizing your own reasoning as an "architect review" is fabrication — the agent must actually run and produce output that you then incorporate.

**Required plan file section** (hook-enforced — plan files without this section are blocked):
```
## Architect Review
- **Reviewer:** [exact agent name that was invoked, e.g., frontend-mobile-development:frontend-developer]
- **Verdict:** [approved / approved with changes / needs revision]
- **Key findings:** [architect's actual output, not your own summary]
- **Adjustments:** [what changed based on feedback, or "none"]
```

**Sequence:** `Explore -> Design approach -> Invoke domain architect via Agent tool -> Incorporate findings -> Write plan file -> ExitPlanMode`

## Pre-Implementation — Context7 (Knowledge Freshness Gate)

**Before writing implementation code**, check whether you're using libraries/frameworks where your training knowledge may be stale.

**Always use Context7 when:**
- The project's CLAUDE.md specifies a library version newer than what you confidently know
- You're about to use an API pattern and aren't 100% certain it's current for the version in use
- A library has had a major version bump (e.g., v3 -> v4, v18 -> v19) — APIs often break across majors
- You're unsure whether a pattern is current or deprecated

**How to use:**
1. `resolve-library-id` — find the library's Context7 ID
2. `query-docs` — fetch current docs for the specific feature you're implementing

**Do NOT use Context7 for:** stable, well-known APIs unlikely to have changed (Node.js core, SQL, HTML/CSS fundamentals, Git).

## Phase 2 — Implementation (Judgment-Based, Use Sparingly)

Consult implementation specialists only when the code involves genuine domain complexity that would benefit from specialist knowledge. Most code — even in non-trivial tasks — is straightforward enough to write directly. Do NOT use specialists as a checkbox exercise.

| Complexity Signal | Specialist | Canonical Source |
|-------------------|-----------|------------------|
| Complex TypeScript generics, conditional types, type inference | `typescript-pro` | `javascript-typescript:typescript-pro` |
| Tricky async patterns, Node.js internals, event loop | `javascript-pro` | `javascript-typescript:javascript-pro` |
| Complex SQL queries, index optimization, window functions | `sql-pro` | `database-design:sql-pro` |
| Performance-sensitive code, profiling, caching | `performance-engineer` | `full-stack-orchestration:performance-engineer` |
| TDD workflow (red-green-refactor discipline) | `tdd-orchestrator` | `tdd-workflows:tdd-orchestrator` |
| Test suite creation, coverage strategy | `test-automator` | `full-stack-orchestration:test-automator` |

**Decision test:** "Would a senior specialist write this meaningfully differently?" If no, skip the specialist call.

## Phase 3 — Review (Tier-Dependent)

| Task Tier | Review Process |
|-----------|---------------|
| **Trivial** | `comprehensive-review:code-reviewer` only |
| **Moderate** | Domain architect reviews implementation (as Agent) + `comprehensive-review:code-reviewer` |
| **Significant** | Same domain architect from Phase 1 reviews implementation (as Agent) + `comprehensive-review:code-reviewer` |

**Security gate:** `comprehensive-review:security-auditor` runs for any auth/authz, data handling, or API security work. Additive to the above, regardless of tier.

## Phase 4 — React (On-Demand, Triggered by Events)

| Trigger | Agent | Canonical Source |
|---------|-------|------------------|
| Any error or test failure | `debugger` | `debugging-toolkit:debugger` |
| Multi-service error investigation | `error-detective` | `error-debugging:error-detective` |
| Production incident | `devops-troubleshooter` | `cicd-automation:devops-troubleshooter` |
| Legacy code or framework migration | `legacy-modernizer` | `code-refactoring:legacy-modernizer` |
| Developer experience friction | `dx-optimizer` | `debugging-toolkit:dx-optimizer` |

## Support Agents (As-Needed)

| Purpose | Agent | Canonical Source |
|---------|-------|------------------|
| Technical documentation | `docs-architect` | `documentation-generation:docs-architect` |
| API/OpenAPI documentation | `api-documenter` | `documentation-generation:api-documenter` |
| Architecture diagrams | `mermaid-expert` | `documentation-generation:mermaid-expert` |
| Market sizing, financials | `startup-analyst` | `startup-business-analyst:startup-analyst` |
| Legal/compliance docs | `legal-advisor` | `hr-legal-compliance:legal-advisor` |
| Mobile development | `mobile-developer` | `frontend-mobile-development:mobile-developer` |

## Canonical Agent Sources (Eliminate Duplicates)

These agents exist in multiple plugins. Use ONLY the canonical source listed:

| Agent | Canonical Source | DO NOT USE |
|-------|-----------------|------------|
| `code-reviewer` | `comprehensive-review:code-reviewer` | code-refactoring, tdd-workflows |
| `test-automator` | `full-stack-orchestration:test-automator` | backend-development |
| `debugger` | `debugging-toolkit:debugger` | error-debugging |
| `security-auditor` | `comprehensive-review:security-auditor` | backend-development, full-stack-orchestration |
| `deployment-engineer` | `cicd-automation:deployment-engineer` | cloud-infrastructure, full-stack-orchestration |
| `performance-engineer` | `full-stack-orchestration:performance-engineer` | backend-development |
| `tdd-orchestrator` | `tdd-workflows:tdd-orchestrator` | backend-development |
| `legacy-modernizer` | `code-refactoring:legacy-modernizer` | dependency-management |
| `cloud-architect` | `cicd-automation:cloud-architect` | cloud-infrastructure |
| `kubernetes-architect` | `cicd-automation:kubernetes-architect` | cloud-infrastructure |
| `terraform-specialist` | `cicd-automation:terraform-specialist` | cloud-infrastructure |

## Parallel Invocation

When multiple specialists are needed and their work is independent, invoke them simultaneously. Example: `architect-review` + `database-architect` + `cloud-architect` for a new service.