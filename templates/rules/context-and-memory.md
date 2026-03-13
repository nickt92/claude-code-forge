# Context Management & Memory

## Compaction Protection

When context is compacted, ALWAYS preserve:
- The current task list and completion status
- All file paths modified in this session
- Key architectural decisions and their rationale
- Active constraints or requirements from the user
- Test commands and verification steps that still need to run

## Session Resumption

When resuming a session (`claude --resume`) or recovering after a crash, you are a new instance with partial context. Before continuing work:
1. Read MEMORY.md for project state and active work
2. Check TaskList for in-progress tasks
3. Run `git status` and `git log --oneline -5` to verify working state
4. Confirm with the user before continuing — do NOT assume where you left off

## Context Efficiency

- Use subagents for codebase investigation — they run in separate context windows, keeping the main conversation clean
- For multi-step features, use TaskCreate at the start — task lists survive compaction
- After parallel agent work, extract key decisions into task updates before continuing
- After compaction, re-orient by checking TaskList and memory files before continuing
- Use `/clear` between unrelated tasks — fresh context beats stale context
- Use `/rename` to name sessions descriptively for easy resumption with `claude --resume`

## Configuration Persistence

After completing work, evaluate whether new conventions, patterns, or decisions should be persisted:

- **Library/tool choices** (e.g., "this project uses Pino, not Winston")
- **Architectural patterns** established (e.g., repository pattern, error handling approach)
- **Scripts or utilities** created that future work should leverage
- **Naming conventions** or coding standards that crystallized
- **Gotchas or pitfalls** that would waste time if hit again

**Process:**
1. Identify what was learned or decided
2. Determine the right home — project CLAUDE.md vs auto-memory vs global CLAUDE.md (rare)
3. **Propose the addition with exact text and target file** — NEVER write unilaterally
4. User approves, modifies, or rejects — only then write it

Maintain context actively — flag entries that may no longer be accurate. The goal: future sessions NEVER repeat solved problems or violate established conventions.