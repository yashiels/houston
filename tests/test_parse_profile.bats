#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$REPO_ROOT/pipeline/lib/parse-profile.sh"
}

@test "parse stitch profile returns valid JSON" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "parse stitch profile has correct name" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.name')"
  [ "$result" = "stitch" ]
}

@test "parse stitch profile has correct priority" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq '.profile.priority')"
  [ "$result" -eq 10 ]
}

@test "parse stitch profile has correct email" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.identity.email')"
  [ "$result" = "yashiel.sookdeo@stitch.money" ]
}

@test "parse stitch profile has github orgs" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq '.platforms.github.orgs | length')"
  [ "$result" -eq 2 ]
}

@test "parse stitch profile has gitlab reviewers" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq '.reviewers.gitlab | has("*")')"
  [ "$result" = "true" ]
}

@test "parse stitch profile has linear teams" {
  run parse_profile "$REPO_ROOT/profiles/stitch.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq '.linear.teams | length')"
  [ "$result" -eq 4 ]
}

@test "parse personal profile returns valid JSON" {
  run parse_profile "$REPO_ROOT/profiles/personal.toml"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "parse personal profile has correct email" {
  run parse_profile "$REPO_ROOT/profiles/personal.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.identity.email')"
  [ "$result" = "yashiel@skyner.co.za" ]
}

@test "parse personal profile has mphocodes as reviewer" {
  run parse_profile "$REPO_ROOT/profiles/personal.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.reviewers.github["*"][0]')"
  [ "$result" = "mphocodes" ]
}

@test "parse nonexistent profile fails" {
  run parse_profile "$REPO_ROOT/profiles/nonexistent.toml"
  [ "$status" -eq 1 ]
}
