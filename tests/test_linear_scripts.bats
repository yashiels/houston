#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "linear-teams.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-teams.sh" ]
}

@test "linear-teams.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-teams.sh --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

@test "linear-teams.sh fails with no API key for apex profile" {
  run bash -c "unset LINEAR_API_KEY; $REPO_ROOT/scripts/linear-teams.sh --profile apex 2>&1"
  [ "$status" -ne 0 ]
}

@test "linear-projects.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-projects.sh" ]
}

@test "linear-projects.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-projects.sh --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

@test "linear-issues.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-issues.sh" ]
}

@test "linear-issues.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-issues.sh --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

@test "linear-get-issue.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-get-issue.sh" ]
}

@test "linear-get-issue.sh requires ISSUE-ID argument" {
  run bash -c "$REPO_ROOT/scripts/linear-get-issue.sh 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
