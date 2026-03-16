#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Database Guard Hook — unit tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
  load '../helpers/test_helper'
  setup_sandbox
  HOOK="$SCRIPT_DIR/hooks/db-guard.sh"
}

teardown() {
  teardown_sandbox
}

# Helper: run hook with given command string
run_hook() {
  local cmd="$1"
  local tmpfile="$TEST_SANDBOX/hook-input.json"
  jq -n --arg c "$cmd" '{"tool_input":{"command":$c}}' > "$tmpfile"
  bash "$HOOK" < "$tmpfile"
}

# ── Fast Path (No DB CLI) ────────────────────────────────────

@test "allows commands without database CLI" {
  run run_hook 'ls -la'
  assert_success
}

@test "allows npm commands" {
  run run_hook 'npm run build'
  assert_success
}

@test "allows git commands" {
  run run_hook 'git log --oneline'
  assert_success
}

# ── DROP TABLE / DATABASE / SCHEMA ────────────────────────────

@test "blocks DROP TABLE via psql" {
  run run_hook 'psql -c "DROP TABLE users"'
  assert_failure 2
  assert_output --partial "BLOCKED"
  assert_output --partial "DROP TABLE"
}

@test "blocks DROP DATABASE via mysql" {
  run run_hook 'mysql -e "DROP DATABASE production"'
  assert_failure 2
  assert_output --partial "DROP TABLE/DATABASE/SCHEMA"
}

@test "blocks DROP SCHEMA via psql" {
  run run_hook 'psql -c "DROP SCHEMA public CASCADE"'
  assert_failure 2
}

@test "blocks drop table (case-insensitive)" {
  run run_hook 'psql -c "drop table users"'
  assert_failure 2
}

@test "blocks DROP TABLE via sqlite3" {
  run run_hook 'sqlite3 db.sqlite "DROP TABLE logs"'
  assert_failure 2
}

@test "blocks DROP TABLE via mongosh" {
  run run_hook 'mongosh --eval "DROP TABLE collections"'
  assert_failure 2
}

# ── TRUNCATE ──────────────────────────────────────────────────

@test "blocks TRUNCATE via psql" {
  run run_hook 'psql -c "TRUNCATE users"'
  assert_failure 2
  assert_output --partial "TRUNCATE"
}

@test "blocks truncate (case-insensitive)" {
  run run_hook 'mysql -e "truncate table orders"'
  assert_failure 2
}

@test "blocks TRUNCATE via sqlite3" {
  run run_hook 'sqlite3 db.sqlite "TRUNCATE sessions"'
  assert_failure 2
}

# ── DELETE FROM without WHERE ─────────────────────────────────

@test "blocks DELETE FROM without WHERE" {
  run run_hook 'psql -c "DELETE FROM users"'
  assert_failure 2
  assert_output --partial "DELETE FROM without a WHERE"
}

@test "blocks delete from without where (case-insensitive)" {
  run run_hook 'mysql -e "delete from orders"'
  assert_failure 2
}

@test "allows DELETE FROM with WHERE" {
  run run_hook 'psql -c "DELETE FROM users WHERE id = 5"'
  assert_success
}

@test "allows delete from with where (case-insensitive)" {
  run run_hook 'mysql -e "delete from users where status = '\''inactive'\''"'
  assert_success
}

# ── ALTER TABLE ... DROP ──────────────────────────────────────

@test "blocks ALTER TABLE DROP COLUMN" {
  run run_hook 'psql -c "ALTER TABLE users DROP COLUMN email"'
  assert_failure 2
  assert_output --partial "ALTER TABLE"
}

@test "blocks alter table drop (case-insensitive)" {
  run run_hook 'mysql -e "alter table orders drop column status"'
  assert_failure 2
}

# ── Safe Queries ──────────────────────────────────────────────

@test "allows SELECT via psql" {
  run run_hook 'psql -c "SELECT * FROM users WHERE id = 1"'
  assert_success
}

@test "allows INSERT via mysql" {
  run run_hook 'mysql -e "INSERT INTO users (name) VALUES ('\''John'\'')"'
  assert_success
}

@test "allows UPDATE via sqlite3" {
  run run_hook 'sqlite3 db.sqlite "UPDATE users SET name = '\''Jane'\'' WHERE id = 1"'
  assert_success
}

@test "allows CREATE TABLE" {
  run run_hook 'psql -c "CREATE TABLE test (id serial PRIMARY KEY, name text)"'
  assert_success
}

@test "allows psql connection test" {
  run run_hook 'psql -c "SELECT 1"'
  assert_success
}

# ── Edge Cases ────────────────────────────────────────────────

@test "handles empty command" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"\"}}" | bash "$0"' "$HOOK"
  assert_success
}

@test "handles malformed JSON input" {
  run bash -c 'echo "not json" | bash "$0" 2>/dev/null' "$HOOK"
  assert_success
}

@test "allows mongosh read queries" {
  run run_hook 'mongosh --eval "db.users.find({})"'
  assert_success
}
