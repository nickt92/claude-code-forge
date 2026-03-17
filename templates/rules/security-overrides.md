# Security Hook Overrides

## When to use forge-override

Security hooks (command-guard, db-guard) block dangerous commands by default.
When a hook blocks a command that the user explicitly wants to run:

1. Explain to the user what was blocked and why
2. Wait for the user to explicitly confirm they want to proceed
3. Retry with `# forge-override: <reason>` as the first line of the command
4. The reason MUST describe the user's intent, not just "user confirmed"

## Rules

- NEVER use forge-override without the user's explicit confirmation in the current conversation
- NEVER pre-emptively add forge-override to avoid a block — let the hook block first
- The reason string must be specific: "dropping test database as part of cleanup" not "user said ok"
- If a command is blocked and the user does NOT confirm, suggest a safer alternative
