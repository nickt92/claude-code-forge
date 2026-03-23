# Pull Request Format

## Structure

PRs follow a consistent format: short summary, changes grouped by layer, and a test plan with checkboxes.

### Subject Line
- Conventional commit format: `feat(scope):`, `fix(scope):`, etc.
- Under 70 characters
- Describes the deliverable, not the implementation

### Body

1. **Summary** — one-line description of what the PR delivers end-to-end
2. **Changes grouped by layer** — use headings that match where the work happened (e.g., Backend, Frontend, Admin, Database, Infrastructure, Documentation). Only include sections that are relevant — skip empty layers.
3. **Test plan** — checkboxes describing what was tested, written as verifiable behaviors

## Rules

- **Group by layer/domain** — not by commit or file
- **Plain language** — describe what the feature does, not how the code works
- **No function names, file paths, class names, or type signatures** in the body — save that for code review
- **Test plan uses behavioral descriptions** — what a reviewer can verify, not internal test names
- **Checkboxes are pre-checked** `[x]` when tests are already passing, unchecked `[ ]` for manual verification TODOs
- **Include top-level test suite results** (e.g., "1,964 tests pass, 73 files, 0 failures") when automated tests exist
- **Keep it scannable** — bullet points, not paragraphs. No walls of text.
- **Commit list is NOT included** — the PR diff and commit tab serve that purpose
- **No AI attribution** — no "Generated with Claude Code" or similar footers