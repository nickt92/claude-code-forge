# Security Model

## Philosophy

Forge hooks are **defense-in-depth** — they add friction against common mistakes, not a security boundary. Claude Code runs user-approved commands in a sandboxed shell. Hooks intercept tool calls to warn or block, but they cannot prevent all possible circumventions.

## Hook Summary

| Hook | Trigger | Guards Against | Limitations |
|:-----|:--------|:---------------|:------------|
| `commit-validator` | `git commit` via Bash | AI attribution, non-conventional format | Only matches direct `git commit` invocations; indirect commits (scripts, aliases) may bypass |
| `architect-gate` | Write/Edit to `~/.claude/plans/` | Plan files without architect review section | Only checks the `plans/` directory; plan content elsewhere is not gated |
| `command-guard` | Bash tool invocations | Destructive commands (`rm -rf /`, `DROP TABLE`, `docker run --privileged`) | Pattern-based detection; obfuscated commands, heredocs, or file-based SQL can bypass |
| `secret-filter` | Bash tool invocations | Credentials in commands (AWS keys, tokens, passwords in flags) | Detects common patterns; encoded, split, or indirect credential passing is not caught |
| `db-guard` | Bash tool invocations | Destructive SQL (`DROP`, `TRUNCATE`, `DELETE FROM` without `WHERE`) | Only detects SQL in direct command strings; `.sql` file execution or ORM calls are not intercepted |
| `session-init` | First user prompt per session | Skipping task classification | Advisory only — nudges behavior, does not enforce |
| `backup-transcript` | Before context compaction | Lost conversation context | Best-effort; relies on Claude Code's compaction event |
| `forge-update-check` | First user prompt per session | Running outdated forge version | Advisory only — prints a notice, does not block |

## Known Gaps

1. **PostToolUse hooks are advisory.** They run after the tool completes and cannot block execution. `session-init`, `backup-transcript`, and `forge-update-check` fall in this category.

2. **Pattern matching is not parsing.** `command-guard`, `secret-filter`, and `db-guard` use regex patterns against the command string. Encoded arguments, variable expansion, heredocs, and piped input can bypass detection.

3. **No file-content scanning.** Hooks inspect the command, not the file being read or written. A `.sql` file containing `DROP TABLE` executed via `psql -f` is not caught by `db-guard`.

4. **Hook scope is `~/.claude/settings.json`.** Hooks apply globally to all Claude Code sessions. There is no per-project hook override mechanism.

5. **Hooks require Claude Code cooperation.** If the Claude Code client changes its tool call format or event naming, hooks may stop firing. Pin to tested Claude Code versions.

## Reporting

If you discover a bypass that represents a meaningful security concern beyond the known gaps above, please open an issue. Pattern-matching improvements are welcome as pull requests.
