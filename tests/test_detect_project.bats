#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$REPO_ROOT/tests/fixtures"
}

@test "detect node project with pnpm" {
  run "$REPO_ROOT/pipeline/detect-project.sh" "$FIXTURES/fake-node-project"
  [ "$status" -eq 0 ]
  lang="$(echo "$output" | jq -r '.lang')"
  pm="$(echo "$output" | jq -r '.packageManager')"
  [ "$lang" = "node" ]
  [ "$pm" = "pnpm" ]
}

@test "detect typescript in node project" {
  run "$REPO_ROOT/pipeline/detect-project.sh" "$FIXTURES/fake-node-project"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq '.typescript')"
  [ "$result" = "true" ]
}

@test "detect go project" {
  run "$REPO_ROOT/pipeline/detect-project.sh" "$FIXTURES/fake-go-project"
  [ "$status" -eq 0 ]
  lang="$(echo "$output" | jq -r '.lang')"
  pm="$(echo "$output" | jq -r '.packageManager')"
  [ "$lang" = "go" ]
  [ "$pm" = "go" ]
}

@test "detect unknown project" {
  tmpdir="$(mktemp -d)"
  run "$REPO_ROOT/pipeline/detect-project.sh" "$tmpdir"
  [ "$status" -eq 0 ]
  lang="$(echo "$output" | jq -r '.lang')"
  [ "$lang" = "unknown" ]
  rm -rf "$tmpdir"
}

@test "detect node test command from package.json" {
  run "$REPO_ROOT/pipeline/detect-project.sh" "$FIXTURES/fake-node-project"
  [ "$status" -eq 0 ]
  testCmd="$(echo "$output" | jq -r '.testCmd')"
  [ "$testCmd" = "pnpm test" ]
}
