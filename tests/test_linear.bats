#!/usr/bin/env bats

# test_linear.bats — Tests for Linear integration functions (pipeline/linear.sh)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$REPO_ROOT/pipeline/linear.sh"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "linear.sh can be sourced" {
  # If we got here, sourcing succeeded in setup()
  # Verify a key function is defined
  declare -f linear_api >/dev/null
}

@test "linear_api fails without API key" {
  unset LINEAR_API_KEY 2>/dev/null || true
  unset SKYNER_LINEAR_API_KEY 2>/dev/null || true
  run linear_api "{ viewer { id } }" "LINEAR_API_KEY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No API key"* ]]
}

@test "linear_find_ticket fails with no keys set" {
  unset LINEAR_API_KEY 2>/dev/null || true
  unset SKYNER_LINEAR_API_KEY 2>/dev/null || true
  run linear_find_ticket "TEST-1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
