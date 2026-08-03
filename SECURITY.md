# Security Model

## Philosophy

Forge hooks are **defense-in-depth** — they add friction against common mistakes, not a security boundary. Claude Code runs user-approved commands in a sandboxed shell. Hooks intercept tool calls to warn or block, but they cannot prevent all possible circumventions.

## Hook Summary

| Hook | Trigger | Guards Against | Limitations |
|:-----|:--------|:---------------|:------------|
| `commit-validator` | PreToolUse (Bash) | AI attribution, non-conventional format | Only matches direct `git commit` invocations; indirect commits (scripts, aliases) may bypass |
| `architect-gate` | PreToolUse (Write/Edit) | Plan files without architect review section; first-edit task classification | Only checks the `plans/` directory; plan content elsewhere is not gated |
| `command-guard` | PreToolUse (Bash) | Fork bombs, downloads piped into a shell, injection via `$(...)`, credentials read and sent to the network | Four checks only — everything else moved to permission rules. Staging a secret through an intermediate file defeats the exfiltration check |
| `db-guard` | PreToolUse (Bash) | Destructive SQL (`DROP`, `TRUNCATE`, `DELETE FROM` without `WHERE`) and `COPY … TO PROGRAM` via CLI tools | Only detects SQL in direct command strings; `.sql` file execution or ORM calls are not intercepted |
| `secret-filter` | PostToolUse (all tools) | Credentials in tool output (AWS keys, GitHub tokens, API keys, PEM keys, env vars) | Advisory only — runs after the tool completes, cannot block or mask output. Detects common patterns; encoded or split credentials are not caught |
| `session-init` | UserPromptSubmit | Skipping task classification; missing document chain for non-trivial projects | Advisory only — nudges behavior, does not enforce |
| `backup-transcript` | PreCompact | Lost conversation context before compaction | Best-effort; relies on Claude Code's compaction event firing |
| `forge-update-check` | UserPromptSubmit | Running outdated forge version | Advisory only — prints a notice, does not block |

## Where enforcement lives

Two layers, and the split matters:

**Permission rules** are the primary layer. Claude Code evaluates them in-process,
before dispatch, against a *parsed* command — it strips environment prefixes and
transparent wrappers, splits compound commands, and matches each part. Precedence
is deny, then ask, then allow, first match wins. There is no bypass from inside a
command.

**Hooks** are the small remainder: the checks that need a relationship between
parts of a command, which a rule cannot express. `command-guard` carries four.

Hooks run regardless of permission mode — Claude Code gates them only on whether
they are configured — so they still apply under `bypassPermissions`.

An earlier version of this document said the opposite of what follows, and it was
wrong in the direction that flattered the design. Corrected against the shipped
binary:

- **Deny rules are honoured under `bypassPermissions`.** The deny checks sit above
  the bypass short-circuit in the permission pipeline, and the SDK's own warning
  string states it: bypass "auto-approves every tool call *(except explicit deny
  rules)* before the callback is consulted."
- **A hook's `ask` does not guarantee a human sees it.** A hook `deny` returns
  before `canUseTool` is consulted. A hook `ask` is handed *to* `canUseTool`, so
  under `--permission-prompt-tool` or an SDK callback it is answered by whatever
  that approver decides. Interactively it is a real prompt; under automation it
  may not be.

So `deny` is the stronger control, not the weaker one. `ask` is right where a
legitimate use exists and a human is the intended judge; `deny` is right where
nothing legitimate exists.

## There is no override token

Versions before 2.0 accepted `# forge-override: <reason>` as the first line of a
command, which made `command-guard` and `db-guard` skip every check for that
command. **It has been removed.**

Its stated security model was that Claude Code's permission prompt would show the
user the full command, including the override comment, before anything ran. That
is false whenever the command is covered by an allow rule, because then there is
no prompt at all — which is the common case, and precisely the case where the
guard was the last thing standing. The override silently converted a block into a
no-op with no human in the loop, on a token the model writes for itself.

The guards now return a permission decision instead:

- **ask** — surfaces the real command to whoever answers permission prompts.
  Used for downloads piped into a shell, injection, credential exfiltration,
  destructive payloads handed to an interpreter, and every destructive SQL
  pattern.
- **deny** — fork bombs and filesystem formatting. Not delegable, and honoured
  under bypass.

The user approving that prompt *is* the override, and it needs nothing added to
the command. For permission rules the equivalent is `forge permissions --except
<rule>`, which records the exception in the manifest where it can be inspected
and reverted.

## Degraded mode

Failing open is not a choice — Claude Code fails open when a hook times out,
regardless of what the hook would have said. What was missing was the difference
between *nothing to check* and *could not check*: with `jq` absent, every guard
exited 0 forever and nothing recorded it.

Both guards now write a `DEGRADED` line to `~/.claude/security.log` when they
cannot inspect a command.

### Audit Trail

```
2026-08-03T14:22:00Z SECRET_DETECTED tool=Bash types="AWS access key"
2026-08-03T14:25:11Z DEGRADED hook=command-guard reason="jq not found; command not inspected"
```

- ISO 8601 UTC timestamp
- Event types: `SECRET_DETECTED`, `DEGRADED`
- **No command strings are logged.** Removing `forge-override` also removed the
  only place forge wrote raw commands — and therefore potentially secrets — into
  its own audit log. `SECRET_DETECTED` records the *kind* of credential found,
  never the value.
- `~/.claude/security.log` and `~/.claude/hook-telemetry.log` are created `0600`
  and rolled at 1 MB. Before 2.0 the security log was `0644` and unbounded.

## Known Gaps

1. **PostToolUse hooks are advisory.** `secret-filter` runs after the tool completes and cannot block execution or mask output. It warns Claude not to repeat detected credentials, but the original output has already been processed.

2. **UserPromptSubmit hooks are advisory.** `session-init` and `forge-update-check` inject context into Claude's prompt but cannot block or modify user input. Claude may not always follow advisory nudges.

3. **Pattern matching is not parsing.** `command-guard`, `secret-filter`, and `db-guard` use regex patterns against command/output strings. Encoded arguments, variable expansion, heredocs, and piped input can bypass detection.

4. **No file-content scanning.** Hooks inspect the command or output, not the file being read or written. A `.sql` file containing `DROP TABLE` executed via `psql -f` is not caught by `db-guard`.

5. **Hook scope is `~/.claude/settings.json`.** Hooks apply globally to all Claude Code sessions. There is no per-project hook override mechanism.

6. **Hooks require Claude Code cooperation.** If the Claude Code client changes its tool call format or event naming, hooks may stop firing. Pin to tested Claude Code versions.

## Reporting

If you discover a bypass that represents a meaningful security concern beyond the known gaps above, please open an issue. Pattern-matching improvements are welcome as pull requests.
