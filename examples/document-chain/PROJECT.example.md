# PROJECT.md

## Product

**Name:** TaskFlow
**One-liner:** A team task management app with real-time collaboration and smart prioritization.
**Target users:** Small engineering teams (5-20 people) who outgrow Trello but don't need Jira's complexity.

## Vision

TaskFlow replaces the spreadsheet-and-Slack workflow with a purpose-built tool that understands engineering workflows. Tasks flow through customizable stages, priorities adjust based on dependencies and deadlines, and the team gets a shared view of what matters most right now.

## Constraints

| Constraint | Detail |
|-----------|--------|
| Timeline | MVP by end of Q2 2026, public beta Q3 |
| Team | 1 full-stack dev (solo founder), AI-assisted development |
| Budget | Bootstrap — cloud costs under $200/month at launch |
| Compliance | SOC 2 not required at launch, but design for it |
| Technical | Must run on a single VPS initially, scale later |

## Stakeholders

| Role | Person | Decisions They Own |
|------|--------|--------------------|
| Product owner | Alex Chen | Feature prioritization, UX direction |
| Technical lead | Alex Chen | Architecture, technology choices |
| Design | Alex Chen (+ AI) | UX patterns, component design |

## Non-Goals

- Enterprise features (SSO, audit logs, compliance dashboards) — deferred to post-launch
- Mobile native app — responsive PWA is sufficient for v1
- Integrations (GitHub, Slack, etc.) — API-first design enables this later
- Self-hosted option — SaaS only at launch

## Key Decisions

| Decision | Choice | Rationale | Date |
|----------|--------|-----------|------|
| Framework | Next.js 15 + App Router | SSR for performance, React ecosystem, good AI tooling support | 2026-01-15 |
| Database | PostgreSQL + Drizzle ORM | Relational fits task data well, Drizzle is type-safe and lightweight | 2026-01-15 |
| Auth | Better Auth | Modern, self-hosted, good DX, avoids vendor lock-in | 2026-01-20 |
| Hosting | Railway | Simple deployment, good free tier for dev, easy scaling path | 2026-02-01 |
| Real-time | Server-Sent Events | Simpler than WebSockets for one-way updates, sufficient for v1 | 2026-02-10 |