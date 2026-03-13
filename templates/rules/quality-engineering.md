# Quality Engineering Standards

## Code Quality

- Write clean, readable, self-documenting code. Match the project's existing naming patterns.
- Enforce type safety — avoid `any` or equivalent escape hatches.
- When modifying shared APIs, interfaces, or contracts — ask whether backward compatibility is required or whether an atomic breaking change is preferred.

## Testing

Target 85% code coverage as a baseline. Adjust based on context:
- **Core business logic, APIs, critical paths** — ALWAYS require comprehensive coverage
- **POCs, prototypes, utility scripts** — coverage is optional, be pragmatic
- **Bug fixes** — write a failing test first that reproduces the bug, then fix

Testing rules:
- Test behavior, not implementation — tests MUST survive refactors
- Follow the testing pyramid: unit (most) > integration (some) > E2E (few, critical paths only)
- Tests MUST be independent, deterministic, and fast — no test depends on another
- Mock at system boundaries (APIs, databases, external services), NOT internal modules
- Include edge cases, error paths, and boundary conditions — not just the happy path
- Name tests as behavior specifications that read as documentation (e.g., `should reject expired tokens`)

## Accessibility

Apply to ALL frontend work:
- Use semantic HTML elements over generic divs/spans
- Add ARIA attributes where semantic HTML is insufficient
- Ensure keyboard navigation for every interactive element
- Meet WCAG 2.1 AA color contrast ratios minimum
- Verify screen reader compatibility for critical user flows

## Performance

Apply to every change:
- Lazy load routes, heavy components, and non-critical resources
- Code split where meaningful bundle reduction is achievable
- Eliminate N+1 queries. Add proper indexes. Paginate large datasets.
- Do NOT prematurely optimize, but do NOT introduce negligent bloat
- Measure before and after for performance-sensitive changes
- Check import cost before adding frontend dependencies — be conscious of bundle size

## Observability

Every backend service MUST include:
- Structured logging (NOT console.log in production) with correlation IDs
- Health check endpoints
- Error tracking with meaningful context, not just stack traces
- PII masking in all logs — NEVER log raw emails, phone numbers, passwords, or tokens

## Documentation

- Document **decisions** (ADRs), not implementations — code MUST be self-documenting
- READMEs for setup and project context, not function-level docs
- Inline comments only where the "why" is not obvious from the code
- API documentation for public interfaces and service boundaries

## Existing Code

- ALWAYS read before modifying — understand existing patterns and conventions
- Match the project's established style, not a generic "best practice" from elsewhere
- When introducing a new pattern, check whether a similar pattern already exists
- Understand the *intent* behind existing patterns before judging them — there may be constraints not immediately visible
- Do NOT refactor surrounding code unless explicitly asked — stay focused on the task