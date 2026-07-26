#!/usr/bin/env bats
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Version Sync — guards against CLI/app version drift
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# The desktop app's Info.plist drifted behind the CLI in 1.3.x
# (CLI 1.3.1 shipped while the app still claimed 1.3.0). These
# tests make that drift a CI failure. Pure grep/sed — no plutil —
# so they run on Linux/Windows CI too.

setup() {
  load '../helpers/test_helper'
}

cli_version() {
  sed -n 's/^FORGE_VERSION="\${FORGE_VERSION:-\(.*\)}"$/\1/p' "$PROJECT_ROOT/lib/manifest.sh"
}

app_version() {
  grep -A1 '<key>CFBundleShortVersionString</key>' "$PROJECT_ROOT/app/ForgeDesktop/Info.plist" \
    | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p'
}

readme_version() {
  sed -n 's/.*badge\/version-\([0-9][0-9.]*\)-.*/\1/p' "$PROJECT_ROOT/README.md" | head -1
}

@test "CLI version is parseable from manifest" {
  run cli_version
  assert_success
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "app Info.plist version matches CLI version" {
  local cli app
  cli="$(cli_version)"
  app="$(app_version)"
  [ -n "$cli" ]
  [ -n "$app" ]
  [ "$cli" = "$app" ]
}

@test "README badge version matches CLI version" {
  local cli badge
  cli="$(cli_version)"
  badge="$(readme_version)"
  [ -n "$badge" ]
  [ "$cli" = "$badge" ]
}
