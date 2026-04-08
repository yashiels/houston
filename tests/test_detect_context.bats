#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  source "$FIXTURES/setup-git-fixtures.sh"
  create_git_fixtures "$FIXTURES"
}

teardown() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  source "$FIXTURES/setup-git-fixtures.sh"
  cleanup_git_fixtures "$FIXTURES"
}

@test "detect stitch context from github remote" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-github-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.name')"
  [ "$result" = "stitch" ]
}

@test "detect stitch context from gitlab remote" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-gitlab-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.name')"
  [ "$result" = "stitch" ]
}

@test "detect platform as github" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-github-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.detected.platform')"
  [ "$result" = "github" ]
}

@test "detect platform as gitlab" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-gitlab-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.detected.platform')"
  [ "$result" = "gitlab" ]
}

@test "detect cli as gh for github" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-github-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.detected.cli')"
  [ "$result" = "gh" ]
}

@test "detect cli as glab for gitlab" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-gitlab-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.detected.cli')"
  [ "$result" = "glab" ]
}

@test "detect personal context from skyner remote" {
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-personal-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.name')"
  [ "$result" = "personal" ]
}

@test "higher priority profile wins" {
  # The fake-github-repo remote contains "stitch" which matches stitch (priority 10).
  # stitch profile (priority 10) should win over personal (priority 5).
  run "$REPO_ROOT/pipeline/detect-context.sh" "$FIXTURES/fake-github-repo"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.name')"
  [ "$result" = "stitch" ]
  priority="$(echo "$output" | jq '.profile.priority')"
  [ "$priority" -eq 10 ]
}

@test "non-git directory fails" {
  tmpdir="$(mktemp -d)"
  run "$REPO_ROOT/pipeline/detect-context.sh" "$tmpdir"
  [ "$status" -eq 1 ]
  rm -rf "$tmpdir"
}
