## Critical Code Rules — NEVER Violate

- No security vulnerabilities (OWASP Top 10 minimum). No `any` escape hatches.
- Proper error handling with meaningful messages — no silent swallowing.
- No TODO/FIXME without a tracking issue. No placeholder/stub implementations.
- Test behavior, not implementation. Mock at system boundaries only.
- When modifying shared APIs or contracts — YOU MUST ask whether backward compatibility is required.