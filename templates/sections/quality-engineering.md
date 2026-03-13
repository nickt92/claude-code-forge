## Engineering Quality Standards

**Testing** — Target 85% code coverage baseline. Bug fixes: write a failing test first, then fix.
- Follow the testing pyramid: unit (most) > integration (some) > E2E (few, critical paths only)
- Tests MUST be independent, deterministic, and fast — no test depends on another
- Include edge cases, error paths, and boundary conditions — not just the happy path

**Accessibility** — Semantic HTML, ARIA attributes, keyboard navigation, WCAG 2.1 AA contrast ratios.

**Performance** — Lazy load non-critical resources, code split where meaningful, eliminate N+1 queries, paginate large datasets. Measure before and after for performance-sensitive changes.

**Observability** — Structured logging with correlation IDs, health check endpoints, error tracking with context, PII masking in all logs.