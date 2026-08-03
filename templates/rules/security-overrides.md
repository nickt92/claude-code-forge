# Security Prompts

## There is no override token

Earlier versions of forge accepted `# forge-override: <reason>` as the first
line of a command, which made the guard hooks skip every check for that command.
That mechanism is gone, and it must not be reintroduced.

It rested on a claim that was false in the common case: that Claude Code's
permission prompt would show the user the full command, including the override,
before anything ran. When the command is covered by an allow rule there is no
prompt at all — so the override silently turned a block into a no-op with no
human in the loop. A comment that the model writes is not consent.

## What happens instead

The guards now return a permission decision rather than blocking outright:

- **ask** — Claude Code shows the real command and waits for the user. This is
  what nearly every guard now returns, and it is also the answer for destructive
  SQL, downloads piped into a shell, and anything that reads a credential and
  sends it somewhere.
- **deny** — reserved for the one pattern with no legitimate use (fork bombs).

The user approving that prompt *is* the override. Nothing needs to be added to
the command.

## How to behave when a guard asks

1. Do not rewrite the command to evade the check. Changing `curl … | bash` into
   `curl -o /tmp/x … && bash /tmp/x` defeats the guard without reducing the
   risk, and it hides the intent from the user.
2. Explain in one line what the guard flagged and why, then let the user decide.
3. If the user declines, offer the safer form — download and read first, add a
   `WHERE` clause, target a specific path.
4. If a guard fires on something genuinely harmless, say so plainly. That is a
   bug worth reporting, not something to work around silently.

## Permission rules

Most dangerous commands are handled by permission rules rather than hooks, and
those are not overridable from inside a command either. If a rule is wrong for
this user's workflow, the fix is `forge permissions --except <rule>`, which
records the exception in the manifest — a deliberate, inspectable choice, not
a per-command bypass.

`forge permissions --explain '<command>'` shows which rule decided a command
and at what precedence.
