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

# ---------------------------------------------------------------------------
# Stub helpers
# ---------------------------------------------------------------------------

make_curl_stub() {
  local stub_dir="$1"
  local response="$2"
  mkdir -p "$stub_dir"
  printf '#!/usr/bin/env bash\necho '"'"'%s'"'"'\n' "$response" > "$stub_dir/curl"
  chmod +x "$stub_dir/curl"
}

# ---------------------------------------------------------------------------
# linear_api_with_vars
# ---------------------------------------------------------------------------

@test "linear_api_with_vars fails without API key" {
  unset LINEAR_API_KEY 2>/dev/null || true
  run linear_api_with_vars "{ viewer { id } }" "{}" "LINEAR_API_KEY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No API key"* ]]
}

@test "linear_api_with_vars sends request with variables" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"viewer":{"id":"abc"}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_api_with_vars "{ viewer { id } }" "{}" "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  rm -rf "$stub_dir"
}

# ---------------------------------------------------------------------------
# linear_list_teams
# ---------------------------------------------------------------------------

@test "linear_list_teams fails without API key" {
  unset LINEAR_API_KEY 2>/dev/null || true
  run linear_list_teams "LINEAR_API_KEY"
  [ "$status" -ne 0 ]
}

@test "linear_list_teams returns array" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"teams":{"nodes":[{"id":"abc","name":"Development","key":"DEV"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_list_teams "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  count="$(echo "$output" | jq 'length')"
  [ "$count" -eq 1 ]
  rm -rf "$stub_dir"
}

# ---------------------------------------------------------------------------
# linear_list_projects
# ---------------------------------------------------------------------------

@test "linear_list_projects returns array" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"projects":{"nodes":[{"id":"p1","name":"Skyner Mono","state":"backlog","description":"","url":"https://linear.app/test"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_list_projects "" "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  name="$(echo "$output" | jq -r '.[0].name')"
  [ "$name" = "Skyner Mono" ]
  rm -rf "$stub_dir"
}

# ---------------------------------------------------------------------------
# linear_resolve_team_id
# ---------------------------------------------------------------------------

@test "linear_resolve_team_id returns empty and fails for unknown team" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"teams":{"nodes":[{"id":"abc","name":"Development"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_resolve_team_id "NonExistent" "LINEAR_API_KEY"
  [ "$status" -ne 0 ]
  rm -rf "$stub_dir"
}

@test "linear_resolve_team_id returns UUID for known team" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"teams":{"nodes":[{"id":"abc-uuid","name":"Development"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_resolve_team_id "Development" "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "abc-uuid" ]
  rm -rf "$stub_dir"
}

# ---------------------------------------------------------------------------
# linear_resolve_member_id
# ---------------------------------------------------------------------------

@test "linear_resolve_member_id matches by email" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"users":{"nodes":[{"id":"uid1","name":"Apex","email":"apex@skyner.co.za"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_resolve_member_id "apex@skyner.co.za" "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "uid1" ]
  rm -rf "$stub_dir"
}

@test "linear_resolve_member_id fails for unknown user" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"users":{"nodes":[]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_resolve_member_id "nobody@example.com" "LINEAR_API_KEY"
  [ "$status" -ne 0 ]
  rm -rf "$stub_dir"
}

# ---------------------------------------------------------------------------
# linear_resolve_label_ids
# ---------------------------------------------------------------------------

@test "linear_resolve_label_ids returns JSON array" {
  local stub_dir
  stub_dir="$(mktemp -d)"
  make_curl_stub "$stub_dir" '{"data":{"issueLabels":{"nodes":[{"id":"lid1","name":"Bug"},{"id":"lid2","name":"Feature"}]}}}'
  PATH="$stub_dir:$PATH" LINEAR_API_KEY="test_key" \
    run linear_resolve_label_ids "Bug,Feature" "" "LINEAR_API_KEY"
  [ "$status" -eq 0 ]
  count="$(echo "$output" | jq 'length')"
  [ "$count" -eq 2 ]
  rm -rf "$stub_dir"
}
