#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$REPO_ROOT/pipeline/lib/parse-profile.sh"
  source "$REPO_ROOT/pipeline/lib/load-profile.sh"
}

@test "load-profile.sh can be sourced" {
  declare -f _load_linear_context >/dev/null
}

@test "_load_linear_context sets LINEAR_KEY_ENV from named profile" {
  _load_linear_context "apex" "$REPO_ROOT"
  [ "$LINEAR_KEY_ENV" = "LINEAR_API_KEY" ]
}

@test "_load_linear_context sets DEFAULT_TEAM from named profile" {
  _load_linear_context "apex" "$REPO_ROOT"
  [ "$DEFAULT_TEAM" = "Development" ]
}

@test "_load_linear_context fails for nonexistent profile" {
  run bash -c "
    source '$REPO_ROOT/pipeline/lib/parse-profile.sh'
    source '$REPO_ROOT/pipeline/lib/load-profile.sh'
    _load_linear_context 'nonexistent-xyz' '$REPO_ROOT' 2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

@test "_load_linear_context uses HOUSTON_PROFILE env var" {
  HOUSTON_PROFILE="apex" _load_linear_context "" "$REPO_ROOT"
  [ "$LINEAR_KEY_ENV" = "LINEAR_API_KEY" ]
}
