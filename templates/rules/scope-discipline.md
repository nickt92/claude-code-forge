# Scope Discipline

## Misclassification Guard

These tasks are frequently downgraded to moderate. They are **significant**:

| Looks moderate, IS significant | Why |
|-------------------------------|-----|
| Greenfield scaffolding with 3+ integrations | It's a new service |
| Adding auth/payments/storage provider | Architectural + multi-file |
| Initial DB schema with RLS/multi-tenancy | Design decisions compound |
| Infrastructure from scratch (CI/CD, Docker) | Cross-cutting, hard to undo |
| "Just wiring up config" across 5+ files | Cumulative complexity = architectural |

"Architecture already decided in CLAUDE.md" does not reduce tier. Documented decisions still need a scoped implementation plan.

## Definition of Done

Before implementing any task, state:
1. Which files/directories will be created or modified
2. What the task does NOT include (explicit exclusions)
3. The condition that means "stop and ask for the next task"

A task without a definition of done will scope-creep. If you find yourself creating files you didn't list, **stop and reassess** — you are likely starting a new task that needs separate classification.

## Delivery Rule

- Deliver what was asked — not more, not less. No gold-plating.
- Flag discovered work (bugs, tech debt, next steps) as separate items rather than bundling.
- When in doubt whether something is in scope, ask.
