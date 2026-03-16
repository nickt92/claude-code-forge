# Security Model

## Philosophy

Forge hooks are **defense-in-depth** — they add friction against common mistakes, not a security boundary. Claude Code runs user-approved commands in a sandboxed shell. Hooks intercept tool calls to warn or block, but they cannot prevent all possible circumventions.

## Hook Summary

| Hook | Trigger | Guards Against | Limitations |
|:-----|:--------|:---------------|:------------|
| `commit-validator` | PreToolUse (Bash) | AI attribution, non-conventional format | Only matches direct `git commit` invocations; indirect commits (scripts, aliases) may bypass |
| `architect-gate` | PreToolUse (Write/Edit) | Plan files without architect review section; first-edit task classification | Only checks the `plans/` directory; plan content elsewhere is not gated |
| `command-guard` | PreToolUse (Bash) | Destructive commands (`rm -rf /`), remote code execution (`curl \| bash`), fork bombs, secret leakage | Pattern-based detection; obfuscated commands, heredocs, or variable expansion can bypass |
| `db-guard` | PreToolUse (Bash) | Destructive SQL (`DROP`, `TRUNCATE`, `DELETE FROM` without `WHERE`) via CLI tools | Only detects SQL in direct command strings; `.sql` file execution or ORM calls are not intercepted |
| `secret-filter` | PostToolUse (all tools) | Credentials in tool output (AWS keys, GitHub tokens, API keys, PEM keys, env vars) | Advisory only — runs after the tool completes, cannot block or mask output. Detects common patterns; encoded or split credentials are not caught |
| `session-init` | UserPromptSubmit | Skipping task classification; missing document chain for non-trivial projects | Advisory only — nudges behavior, does not enforce |
| `backup-transcript` | PreCompact | Lost conversation context before compaction | Best-effort; relies on Claude Code's compaction event firing |
| `forge-update-check` | UserPromptSubmit | Running outdated forge version | Advisory only — prints a notice, does not block |

## Known Gaps

1. **PostToolUse hooks are advisory.** `secret-filter` runs after the tool completes and cannot block execution or mask output. It warns Claude not to repeat detected credentials, but the original output has already been processed.

2. **UserPromptSubmit hooks are advisory.** `session-init` and `forge-update-check` inject context into Claude's prompt but cannot block or modify user input. Claude may not always follow advisory nudges.

3. **Pattern matching is not parsing.** `command-guard`, `secret-filter`, and `db-guard` use regex patterns against command/output strings. Encoded arguments, variable expansion, heredocs, and piped input can bypass detection.

4. **No file-content scanning.** Hooks inspect the command or output, not the file being read or written. A `.sql` file containing `DROP TABLE` executed via `psql -f` is not caught by `db-guard`.

5. **Hook scope is `~/.claude/settings.json`.** Hooks apply globally to all Claude Code sessions. There is no per-project hook override mechanism.

6. **Hooks require Claude Code cooperation.** If the Claude Code client changes its tool call format or event naming, hooks may stop firing. Pin to tested Claude Code versions.

## Reporting

If you discover a bypass that represents a meaningful security concern beyond the known gaps above, please open an issue. Pattern-matching improvements are welcome as pull requests.
