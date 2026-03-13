# ROADMAP.md

## Overview

**Project:** TaskFlow
**Current phase:** Phase 2 — Core Features
**Last updated:** 2026-03-10

## Phase 1 — Foundation

**Status:** Complete
**Target:** January 2026
**Dependencies:** None

### Deliverables
- [x] Project scaffolding (Next.js 15, PostgreSQL, Drizzle)
- [x] Authentication (signup, login, password reset)
- [x] Database schema for users, workspaces, tasks
- [x] Basic task CRUD API
- [x] CI pipeline (lint, type-check, test)

### Milestone
Users can sign up, create a workspace, and manage tasks via API.

## Phase 2 — Core Features

**Status:** In Progress
**Target:** March 2026
**Dependencies:** Phase 1 complete

### Deliverables
- [x] Board view with default columns
- [ ] Drag-and-drop task movement
- [ ] Custom columns (add, rename, reorder)
- [ ] Team invitations and role-based access
- [ ] Real-time updates via SSE

### Milestone
A team can use the board to manage tasks collaboratively in real time.

## Phase 3 — Polish & Launch

**Status:** Planned
**Target:** May 2026
**Dependencies:** Phase 2 complete

### Deliverables
- [ ] Smart prioritization engine
- [ ] Activity feed
- [ ] Onboarding flow for new users
- [ ] Landing page and docs
- [ ] Performance optimization (< 1s initial load)
- [ ] Security audit

### Milestone
Product is ready for public beta — stable, fast, and usable without documentation.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Real-time complexity | SSE may not handle high-frequency updates | Start with polling fallback, upgrade to WebSockets if needed |
| Solo developer bottleneck | All work depends on one person | Prioritize ruthlessly, defer nice-to-haves, leverage AI tooling |
| Database scaling | Single PostgreSQL may hit limits | Design for read replicas from the start, add connection pooling early |