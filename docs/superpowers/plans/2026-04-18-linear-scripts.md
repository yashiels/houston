# Linear Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 9 Linear API scripts and skills to Houston so agents can browse and manage Linear teams, projects, and issues via `/houston:linear-*` skill invocations, backed by two new agent-identity profiles (apex, astra).

**Architecture:** Each script in `scripts/` is a standalone executable that sources `pipeline/linear.sh` (GraphQL primitives) and `pipeline/lib/load-profile.sh` (profile resolution). New library functions in `pipeline/linear.sh` handle all GraphQL queries, mutations, and name→UUID resolution. Skills in `commands/` define the agent routine: which script to run, in what order, and how to present results.

**Tech Stack:** Bash, curl, jq, Linear GraphQL API (`https://api.linear.app/graphql`), bats (test runner via `npx bats`).

---

## File Map

**Created:**
- `profiles/apex.toml` — agent profile for apex
- `profiles/astra.toml` — agent profile for astra
- `pipeline/lib/load-profile.sh` — profile resolution helper (--profile / HOUSTON_PROFILE / git detect)
- `scripts/linear-teams.sh`
- `scripts/linear-projects.sh`
- `scripts/linear-issues.sh`
- `scripts/linear-get-issue.sh`
- `scripts/linear-create-issue.sh`
- `scripts/linear-update-issue.sh`
- `scripts/linear-create-project.sh`
- `scripts/linear-update-project.sh`
- `scripts/linear-comment.sh`
- `commands/linear-teams.md`
- `commands/linear-projects.md`
- `commands/linear-issues.md`
- `commands/linear-get-issue.md`
- `commands/linear-create-issue.md`
- `commands/linear-update-issue.md`
- `commands/linear-create-project.md`
- `commands/linear-update-project.md`
- `commands/linear-comment.md`
- `tests/test_load_profile.bats`
- `tests/test_linear_scripts.bats`

**Modified:**
- `profiles/schema.toml` — add `type` and `[owners]` fields
- `pipeline/lib/parse-profile.sh` — add "owners" to parsed sections
- `pipeline/linear.sh` — add 11 new functions
- `tests/test_linear.bats` — add tests for new library functions
- `tests/test_parse_profile.bats` — add tests for new profile fields

---

## Task 1: Agent Profiles and Schema

**Files:**
- Modify: `profiles/schema.toml`
- Modify: `pipeline/lib/parse-profile.sh`
- Create: `profiles/apex.toml`
- Create: `profiles/astra.toml`
- Modify: `tests/test_parse_profile.bats`

- [ ] **Step 1.1: Write failing tests for new profile fields**

Append to `tests/test_parse_profile.bats`:

```bash
@test "parse apex profile returns valid JSON" {
  run parse_profile "$REPO_ROOT/profiles/apex.toml"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "parse apex profile has type agent" {
  run parse_profile "$REPO_ROOT/profiles/apex.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.profile.type')"
  [ "$result" = "agent" ]
}

@test "parse apex profile has owners" {
  run parse_profile "$REPO_ROOT/profiles/apex.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.owners.users[0]')"
  [ "$result" = "yashiels" ]
}

@test "parse apex profile has correct linear org" {
  run parse_profile "$REPO_ROOT/profiles/apex.toml"
  [ "$status" -eq 0 ]
  result="$(echo "$output" | jq -r '.linear.org')"
  [ "$result" = "Skyner Group" ]
}
```

- [ ] **Step 1.2: Run tests to confirm they fail**

```bash
npx bats tests/test_parse_profile.bats
```

Expected: 4 new tests FAIL (apex.toml does not exist yet).

- [ ] **Step 1.3: Update `profiles/schema.toml`**

Add after the `[profile]` section block comment for `priority`:

```toml
type = ""           # [optional] "agent" or "human" — omit for human profiles
```

Add a new section before `[detect]`:

```toml
[owners]
users = []          # [agent profiles only] human git users this agent works under
```

- [ ] **Step 1.4: Update `pipeline/lib/parse-profile.sh` to parse `[owners]` section**

In the awk script, find the line:
```
split("profile,identity,linear,platforms,reviewers,detect", top_sections, ",")
```
Replace with:
```
split("profile,identity,linear,platforms,owners,reviewers,detect", top_sections, ",")
```

Also find:
```
    for (ts = 1; ts <= 6; ts++) {
```
Replace with:
```
    for (ts = 1; ts <= 7; ts++) {
```

- [ ] **Step 1.5: Create `profiles/apex.toml`**

```toml
# Apex — AI agent for Skyner / Nexion work
[profile]
name = "apex"
priority = 1
type = "agent"

[identity]
name = "Apex"
email = "apex@skyner.co.za"
git_user = "apex-skyner"

[linear]
api_key_env = "LINEAR_API_KEY"
org = "Skyner Group"
default_team = "Development"
teams = ["Development"]

[platforms.github]
orgs = ["yashiels", "skynergroup"]

[owners]
users = ["yashiels", "mphocodes"]

[detect]
remote_patterns = []
```

- [ ] **Step 1.6: Create `profiles/astra.toml`**

```toml
# Astra — AI agent for Skyner / Nexion work
[profile]
name = "astra"
priority = 1
type = "agent"

[identity]
name = "Astra"
email = "astra@skyner.co.za"
git_user = "astra-skyner"

[linear]
api_key_env = "ASTRA_LINEAR_API_KEY"
org = "Skyner Group"
default_team = "Development"
teams = ["Development"]

[platforms.github]
orgs = ["yashiels", "skynergroup"]

[owners]
users = ["yashiels", "mphocodes"]

[detect]
remote_patterns = []
```

- [ ] **Step 1.7: Run tests to confirm they pass**

```bash
npx bats tests/test_parse_profile.bats
```

Expected: all tests pass including the 4 new ones.

- [ ] **Step 1.8: Commit**

```bash
git add profiles/schema.toml profiles/apex.toml profiles/astra.toml \
        pipeline/lib/parse-profile.sh tests/test_parse_profile.bats
git commit -m "feat(profiles): add apex and astra agent profiles with owners field"
```

---

## Task 2: Profile Loader Helper

**Files:**
- Create: `pipeline/lib/load-profile.sh`
- Create: `tests/test_load_profile.bats`

- [ ] **Step 2.1: Write failing tests**

Create `tests/test_load_profile.bats`:

```bash
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
```

- [ ] **Step 2.2: Run tests to confirm they fail**

```bash
npx bats tests/test_load_profile.bats
```

Expected: FAIL — `load-profile.sh` does not exist yet.

- [ ] **Step 2.3: Create `pipeline/lib/load-profile.sh`**

```bash
#!/usr/bin/env bash
# load-profile.sh — Resolve and load a Houston profile for linear scripts.
# Source this file (after parse-profile.sh) and call:
#   _load_linear_context [profile_name] [houston_dir]
# Sets globals: PROFILE_JSON, LINEAR_KEY_ENV, DEFAULT_TEAM

_load_linear_context() {
  local profile_name="${1:-}"
  local houston_dir="${2:-}"

  # Fall back to HOUSTON_PROFILE env var
  if [[ -z "$profile_name" && -n "${HOUSTON_PROFILE:-}" ]]; then
    profile_name="$HOUSTON_PROFILE"
  fi

  if [[ -n "$profile_name" ]]; then
    local profile_file="${houston_dir}/profiles/${profile_name}.toml"
    if [[ ! -f "$profile_file" ]]; then
      echo '{"error":"Profile not found: '"$profile_name"'"}' >&2
      return 1
    fi
    PROFILE_JSON="$(parse_profile "$profile_file")"
  else
    PROFILE_JSON="$("${houston_dir}/pipeline/detect-context.sh" "$(pwd)" "${houston_dir}/profiles" 2>/dev/null)" || {
      echo '{"error":"No profile detected — use --profile NAME or set HOUSTON_PROFILE"}' >&2
      return 1
    }
  fi

  LINEAR_KEY_ENV="$(echo "$PROFILE_JSON" | jq -r '.linear.api_key_env // "LINEAR_API_KEY"')"
  DEFAULT_TEAM="$(echo "$PROFILE_JSON" | jq -r '.linear.default_team // empty')"
}
```

- [ ] **Step 2.4: Run tests to confirm they pass**

```bash
npx bats tests/test_load_profile.bats
```

Expected: all 5 tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add pipeline/lib/load-profile.sh tests/test_load_profile.bats
git commit -m "feat(pipeline): add profile loader helper for linear scripts"
```

---

## Task 3: Library Extensions

**Files:**
- Modify: `pipeline/linear.sh`
- Modify: `tests/test_linear.bats`

Append 11 new functions to `pipeline/linear.sh`. Each function follows the same conventions as existing functions: positional args, optional `key_env` last (defaults to `LINEAR_API_KEY`), JSON to stdout, errors to stderr.

- [ ] **Step 3.1: Write failing tests**

Append to `tests/test_linear.bats`:

```bash
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
```

- [ ] **Step 3.2: Run tests to confirm they fail**

```bash
npx bats tests/test_linear.bats
```

Expected: existing 3 pass, new tests FAIL (functions not defined).

- [ ] **Step 3.3: Append `linear_api_with_vars` to `pipeline/linear.sh`**

```bash
# ---------------------------------------------------------------------------
# linear_api_with_vars <graphql-query> <variables-json> [api-key-env]
# GraphQL request with variables object. Avoids string interpolation for
# complex inputs (mutations with dynamic fields).
# ---------------------------------------------------------------------------
linear_api_with_vars() {
  local query="$1"
  local vars_json="$2"
  local key_env="${3:-LINEAR_API_KEY}"
  local api_key="${!key_env}"

  if [ -z "$api_key" ]; then
    echo '{"error":"No API key found in env var '"$key_env"'"}' >&2
    return 1
  fi

  local payload
  payload=$(jq -n --arg q "$query" --argjson v "$vars_json" \
    '{"query": $q, "variables": $v}')

  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $api_key" \
    -H "Content-Type: application/json" \
    -d "$payload"
}
```

- [ ] **Step 3.4: Append query functions to `pipeline/linear.sh`**

```bash
# ---------------------------------------------------------------------------
# linear_list_teams [api-key-env]
# List all teams in the workspace.
# Returns JSON array of {id, name, key}.
# ---------------------------------------------------------------------------
linear_list_teams() {
  local key_env="${1:-LINEAR_API_KEY}"
  linear_api '{ teams { nodes { id name key } } }' "$key_env" | \
    jq '.data.teams.nodes // []'
}

# ---------------------------------------------------------------------------
# linear_list_projects [team-id] [api-key-env]
# List projects. Scoped to team if team-id provided, otherwise all projects.
# Returns JSON array of {id, name, state, description, url}.
# ---------------------------------------------------------------------------
linear_list_projects() {
  local team_id="${1:-}"
  local key_env="${2:-LINEAR_API_KEY}"

  if [[ -n "$team_id" ]]; then
    linear_api "{ team(id: \"$team_id\") { projects { nodes { id name state description url } } } }" \
      "$key_env" | jq '.data.team.projects.nodes // []'
  else
    linear_api '{ projects(first: 50) { nodes { id name state description url } } }' \
      "$key_env" | jq '.data.projects.nodes // []'
  fi
}

# ---------------------------------------------------------------------------
# linear_list_issues [team-id] [project-id] [state] [assignee-id] [limit] [api-key-env]
# List issues with optional filters. Pass empty string to skip a filter.
# Returns JSON array of {id, identifier, title, priority, state, assignee, project, labels, url}.
# ---------------------------------------------------------------------------
linear_list_issues() {
  local team_id="${1:-}"
  local project_id="${2:-}"
  local state_filter="${3:-}"
  local assignee_id="${4:-}"
  local limit="${5:-50}"
  local key_env="${6:-LINEAR_API_KEY}"

  local filter="{}"
  [[ -n "$team_id" ]]      && filter=$(echo "$filter" | jq --arg v "$team_id"      '. + {team:     {id:   {eq: $v}}}')
  [[ -n "$project_id" ]]   && filter=$(echo "$filter" | jq --arg v "$project_id"   '. + {project:  {id:   {eq: $v}}}')
  [[ -n "$state_filter" ]] && filter=$(echo "$filter" | jq --arg v "$state_filter" '. + {state:    {name: {eq: $v}}}')
  [[ -n "$assignee_id" ]]  && filter=$(echo "$filter" | jq --arg v "$assignee_id"  '. + {assignee: {id:   {eq: $v}}}')

  local query='query($filter: IssueFilter, $first: Int) {
    issues(filter: $filter, first: $first) {
      nodes {
        id identifier title priority url
        state { name }
        assignee { name email }
        project { id name }
        labels { nodes { name } }
      }
    }
  }'

  linear_api_with_vars "$query" \
    "$(jq -n --argjson f "$filter" --argjson l "$limit" '{"filter": $f, "first": $l}')" \
    "$key_env" | jq '.data.issues.nodes // []'
}
```

- [ ] **Step 3.5: Append resolution helpers to `pipeline/linear.sh`**

```bash
# ---------------------------------------------------------------------------
# linear_resolve_team_id <name> [api-key-env]
# Resolve team name to internal UUID. Outputs UUID on stdout.
# ---------------------------------------------------------------------------
linear_resolve_team_id() {
  local name="$1"
  local key_env="${2:-LINEAR_API_KEY}"

  local team_id
  team_id=$(linear_api '{ teams { nodes { id name } } }' "$key_env" | \
    jq -r --arg n "$name" '.data.teams.nodes[] | select(.name == $n) | .id // empty')

  if [[ -z "$team_id" ]]; then
    echo '{"error":"Team not found: '"$name"'"}' >&2
    return 1
  fi
  echo "$team_id"
}

# ---------------------------------------------------------------------------
# linear_resolve_project_id <name> [team-id] [api-key-env]
# Resolve project name to internal UUID. Outputs UUID on stdout.
# ---------------------------------------------------------------------------
linear_resolve_project_id() {
  local name="$1"
  local team_id="${2:-}"
  local key_env="${3:-LINEAR_API_KEY}"

  local project_id
  if [[ -n "$team_id" ]]; then
    project_id=$(linear_api "{ team(id: \"$team_id\") { projects { nodes { id name } } } }" \
      "$key_env" | jq -r --arg n "$name" \
      '.data.team.projects.nodes[] | select(.name == $n) | .id // empty')
  else
    project_id=$(linear_api '{ projects(first: 50) { nodes { id name } } }' "$key_env" | \
      jq -r --arg n "$name" '.data.projects.nodes[] | select(.name == $n) | .id // empty')
  fi

  if [[ -z "$project_id" ]]; then
    echo '{"error":"Project not found: '"$name"'"}' >&2
    return 1
  fi
  echo "$project_id"
}

# ---------------------------------------------------------------------------
# linear_resolve_member_id <name-or-email> [api-key-env]
# Resolve a display name or email to a Linear user UUID. Outputs UUID on stdout.
# ---------------------------------------------------------------------------
linear_resolve_member_id() {
  local name_or_email="$1"
  local key_env="${2:-LINEAR_API_KEY}"

  local member_id
  member_id=$(linear_api '{ users { nodes { id name email } } }' "$key_env" | \
    jq -r --arg q "$name_or_email" \
    '[.data.users.nodes[] | select(.name == $q or .email == $q) | .id][0] // empty')

  if [[ -z "$member_id" ]]; then
    echo '{"error":"Member not found: '"$name_or_email"'"}' >&2
    return 1
  fi
  echo "$member_id"
}

# ---------------------------------------------------------------------------
# linear_resolve_label_ids <"Label1,Label2"> [team-id] [api-key-env]
# Resolve comma-separated label names to a JSON array of UUIDs.
# ---------------------------------------------------------------------------
linear_resolve_label_ids() {
  local label_names_csv="$1"
  local team_id="${2:-}"
  local key_env="${3:-LINEAR_API_KEY}"

  local labels_json
  if [[ -n "$team_id" ]]; then
    labels_json=$(linear_api "{ team(id: \"$team_id\") { labels { nodes { id name } } } }" \
      "$key_env" | jq '.data.team.labels.nodes // []')
  else
    labels_json=$(linear_api '{ issueLabels { nodes { id name } } }' \
      "$key_env" | jq '.data.issueLabels.nodes // []')
  fi

  local ids="[]"
  IFS=',' read -ra label_names <<< "$label_names_csv"
  for label_name in "${label_names[@]}"; do
    label_name="${label_name#"${label_name%%[! ]*}"}"
    label_name="${label_name%"${label_name##*[! ]}"}"
    local lid
    lid=$(echo "$labels_json" | jq -r --arg n "$label_name" \
      '.[] | select(.name == $n) | .id // empty')
    [[ -n "$lid" ]] && ids=$(echo "$ids" | jq --arg id "$lid" '. + [$id]')
  done

  echo "$ids"
}
```

- [ ] **Step 3.6: Append mutation functions to `pipeline/linear.sh`**

```bash
# ---------------------------------------------------------------------------
# linear_create_issue <team-id> <title> [description] [project-id] [priority]
#                     [assignee-id] [label-ids-json] [parent-identifier] [api-key-env]
# Create a new issue. label-ids-json must be a JSON array string e.g. '["id1"]'.
# parent-identifier is the human identifier e.g. "DEV-42" (resolved internally).
# ---------------------------------------------------------------------------
linear_create_issue() {
  local team_id="$1"
  local title="$2"
  local description="${3:-}"
  local project_id="${4:-}"
  local priority="${5:-}"
  local assignee_id="${6:-}"
  local label_ids="${7:-}"
  local parent_identifier="${8:-}"
  local key_env="${9:-LINEAR_API_KEY}"

  local input="{}"
  input=$(echo "$input" | jq --arg v "$team_id" '. + {teamId: $v}')
  input=$(echo "$input" | jq --arg v "$title"   '. + {title: $v}')
  [[ -n "$description" ]] && input=$(echo "$input" | jq --arg v "$description" '. + {description: $v}')
  [[ -n "$project_id" ]]  && input=$(echo "$input" | jq --arg v "$project_id"  '. + {projectId: $v}')
  [[ -n "$priority" ]]    && input=$(echo "$input" | jq --argjson v "$priority" '. + {priority: $v}')
  [[ -n "$assignee_id" ]] && input=$(echo "$input" | jq --arg v "$assignee_id" '. + {assigneeId: $v}')
  if [[ -n "$label_ids" && "$label_ids" != "[]" ]]; then
    input=$(echo "$input" | jq --argjson v "$label_ids" '. + {labelIds: $v}')
  fi

  if [[ -n "$parent_identifier" ]]; then
    local parent_uuid
    parent_uuid=$(linear_api "{ issue(id: \"$parent_identifier\") { id } }" "$key_env" | \
      jq -r '.data.issue.id // empty')
    [[ -n "$parent_uuid" ]] && input=$(echo "$input" | jq --arg v "$parent_uuid" '. + {parentId: $v}')
  fi

  local query='mutation($input: IssueCreateInput!) {
    issueCreate(input: $input) {
      success
      issue { id identifier title url }
    }
  }'

  linear_api_with_vars "$query" "{\"input\": $input}" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_update_issue <identifier> [title] [description] [project-id] [priority]
#                     [assignee-id] [label-ids-json] [parent-uuid] [api-key-env]
# Update an issue. Pass empty string to skip a field. identifier is e.g. "DEV-42".
# ---------------------------------------------------------------------------
linear_update_issue() {
  local identifier="$1"
  local title="${2:-}"
  local description="${3:-}"
  local project_id="${4:-}"
  local priority="${5:-}"
  local assignee_id="${6:-}"
  local label_ids="${7:-}"
  local parent_id="${8:-}"
  local key_env="${9:-LINEAR_API_KEY}"

  local issue_uuid
  issue_uuid=$(linear_api "{ issue(id: \"$identifier\") { id } }" "$key_env" | \
    jq -r '.data.issue.id // empty')

  if [[ -z "$issue_uuid" ]]; then
    echo '{"error":"Issue not found","identifier":"'"$identifier"'"}' >&2
    return 1
  fi

  local input="{}"
  [[ -n "$title" ]]       && input=$(echo "$input" | jq --arg v "$title"       '. + {title: $v}')
  [[ -n "$description" ]] && input=$(echo "$input" | jq --arg v "$description" '. + {description: $v}')
  [[ -n "$project_id" ]]  && input=$(echo "$input" | jq --arg v "$project_id"  '. + {projectId: $v}')
  [[ -n "$priority" ]]    && input=$(echo "$input" | jq --argjson v "$priority" '. + {priority: $v}')
  [[ -n "$assignee_id" ]] && input=$(echo "$input" | jq --arg v "$assignee_id" '. + {assigneeId: $v}')
  if [[ -n "$label_ids" && "$label_ids" != "[]" ]]; then
    input=$(echo "$input" | jq --argjson v "$label_ids" '. + {labelIds: $v}')
  fi
  [[ -n "$parent_id" ]] && input=$(echo "$input" | jq --arg v "$parent_id" '. + {parentId: $v}')

  local query='mutation($id: String!, $input: IssueUpdateInput!) {
    issueUpdate(id: $id, input: $input) {
      success
      issue { id identifier title url }
    }
  }'

  linear_api_with_vars "$query" \
    "$(jq -n --arg id "$issue_uuid" --argjson inp "$input" '{"id": $id, "input": $inp}')" \
    "$key_env"
}

# ---------------------------------------------------------------------------
# linear_create_project <team-id> <name> [description] [state] [api-key-env]
# state: backlog|planned|started|paused|completed|cancelled (default: backlog)
# ---------------------------------------------------------------------------
linear_create_project() {
  local team_id="$1"
  local name="$2"
  local description="${3:-}"
  local state="${4:-backlog}"
  local key_env="${5:-LINEAR_API_KEY}"

  local input="{}"
  input=$(echo "$input" | jq --arg v "$team_id" '. + {teamIds: [$v]}')
  input=$(echo "$input" | jq --arg v "$name"    '. + {name: $v}')
  input=$(echo "$input" | jq --arg v "$state"   '. + {state: $v}')
  [[ -n "$description" ]] && input=$(echo "$input" | jq --arg v "$description" '. + {description: $v}')

  local query='mutation($input: ProjectCreateInput!) {
    projectCreate(input: $input) {
      success
      project { id name state url }
    }
  }'

  linear_api_with_vars "$query" "{\"input\": $input}" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_update_project <project-id> [name] [description] [state] [api-key-env]
# project-id must be the internal UUID.
# ---------------------------------------------------------------------------
linear_update_project() {
  local project_id="$1"
  local name="${2:-}"
  local description="${3:-}"
  local state="${4:-}"
  local key_env="${5:-LINEAR_API_KEY}"

  local input="{}"
  [[ -n "$name" ]]        && input=$(echo "$input" | jq --arg v "$name"        '. + {name: $v}')
  [[ -n "$description" ]] && input=$(echo "$input" | jq --arg v "$description" '. + {description: $v}')
  [[ -n "$state" ]]       && input=$(echo "$input" | jq --arg v "$state"       '. + {state: $v}')

  local query='mutation($id: String!, $input: ProjectUpdateInput!) {
    projectUpdate(id: $id, input: $input) {
      success
      project { id name state url }
    }
  }'

  linear_api_with_vars "$query" \
    "$(jq -n --arg id "$project_id" --argjson inp "$input" '{"id": $id, "input": $inp}')" \
    "$key_env"
}
```

- [ ] **Step 3.7: Run all library tests**

```bash
npx bats tests/test_linear.bats
```

Expected: all tests pass (3 existing + all new).

- [ ] **Step 3.8: Commit**

```bash
git add pipeline/linear.sh tests/test_linear.bats
git commit -m "feat(linear): add query, resolution, and mutation functions"
```

---

## Task 4: Read Scripts

**Files:**
- Create: `scripts/linear-teams.sh`
- Create: `scripts/linear-projects.sh`
- Create: `scripts/linear-issues.sh`
- Create: `scripts/linear-get-issue.sh`
- Create: `tests/test_linear_scripts.bats`

- [ ] **Step 4.1: Write failing tests**

Create `tests/test_linear_scripts.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# ---------------------------------------------------------------------------
# linear-teams.sh
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# linear-projects.sh
# ---------------------------------------------------------------------------

@test "linear-projects.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-projects.sh" ]
}

@test "linear-projects.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-projects.sh --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

# ---------------------------------------------------------------------------
# linear-issues.sh
# ---------------------------------------------------------------------------

@test "linear-issues.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-issues.sh" ]
}

@test "linear-issues.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-issues.sh --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

# ---------------------------------------------------------------------------
# linear-get-issue.sh
# ---------------------------------------------------------------------------

@test "linear-get-issue.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-get-issue.sh" ]
}

@test "linear-get-issue.sh requires ISSUE-ID argument" {
  run bash -c "$REPO_ROOT/scripts/linear-get-issue.sh 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
```

- [ ] **Step 4.2: Run tests to confirm they fail**

```bash
npx bats tests/test_linear_scripts.bats
```

Expected: all tests FAIL (scripts don't exist yet).

- [ ] **Step 4.3: Create `scripts/linear-teams.sh`**

```bash
#!/usr/bin/env bash
# linear-teams.sh — List all Linear teams in the workspace.
# Usage: linear-teams.sh [--profile NAME]
# Output: JSON array of {id, name, key}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROFILE_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) PROFILE_OVERRIDE="$2"; shift ;;
    -h|--help) echo "Usage: linear-teams.sh [--profile NAME]" >&2; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"
linear_list_teams "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-teams.sh`

- [ ] **Step 4.4: Create `scripts/linear-projects.sh`**

```bash
#!/usr/bin/env bash
# linear-projects.sh — List Linear projects, scoped to a team.
# Usage: linear-projects.sh [--team TEAM_NAME] [--profile NAME]
# Output: JSON array of {id, name, state, description, url}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROFILE_OVERRIDE=""
TEAM_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) PROFILE_OVERRIDE="$2"; shift ;;
    --team)    TEAM_NAME="$2"; shift ;;
    -h|--help) echo "Usage: linear-projects.sh [--team TEAM_NAME] [--profile NAME]" >&2; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

TEAM="${TEAM_NAME:-$DEFAULT_TEAM}"
if [[ -z "$TEAM" ]]; then
  echo '{"error":"No team specified and no default_team in profile"}' >&2
  exit 1
fi

TEAM_ID=$(linear_resolve_team_id "$TEAM" "$LINEAR_KEY_ENV")
linear_list_projects "$TEAM_ID" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-projects.sh`

- [ ] **Step 4.5: Create `scripts/linear-issues.sh`**

```bash
#!/usr/bin/env bash
# linear-issues.sh — List Linear issues with optional filters.
# Usage: linear-issues.sh [--project NAME_OR_UUID] [--team NAME] [--state STATE]
#                         [--assignee NAME_OR_EMAIL] [--limit N] [--profile NAME]
# Output: JSON array of {id, identifier, title, priority, state, assignee, project, labels, url}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROFILE_OVERRIDE=""
TEAM_NAME=""
PROJECT_ARG=""
STATE_FILTER=""
ASSIGNEE=""
LIMIT="50"

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)  PROFILE_OVERRIDE="$2"; shift ;;
    --team)     TEAM_NAME="$2"; shift ;;
    --project)  PROJECT_ARG="$2"; shift ;;
    --state)    STATE_FILTER="$2"; shift ;;
    --assignee) ASSIGNEE="$2"; shift ;;
    --limit)    LIMIT="$2"; shift ;;
    -h|--help)
      echo "Usage: linear-issues.sh [--project NAME_OR_UUID] [--team NAME] [--state STATE] [--assignee NAME_OR_EMAIL] [--limit N] [--profile NAME]" >&2
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

TEAM="${TEAM_NAME:-$DEFAULT_TEAM}"
TEAM_ID=""
PROJECT_ID=""
ASSIGNEE_ID=""

if [[ -n "$TEAM" ]]; then
  TEAM_ID=$(linear_resolve_team_id "$TEAM" "$LINEAR_KEY_ENV") || true
fi

if [[ -n "$PROJECT_ARG" ]]; then
  # 36-char UUID passthrough, otherwise resolve by name
  if [[ "${#PROJECT_ARG}" -eq 36 && "$PROJECT_ARG" =~ ^[0-9a-f-]+$ ]]; then
    PROJECT_ID="$PROJECT_ARG"
  else
    PROJECT_ID=$(linear_resolve_project_id "$PROJECT_ARG" "$TEAM_ID" "$LINEAR_KEY_ENV")
  fi
fi

if [[ -n "$ASSIGNEE" ]]; then
  ASSIGNEE_ID=$(linear_resolve_member_id "$ASSIGNEE" "$LINEAR_KEY_ENV") || true
fi

linear_list_issues "$TEAM_ID" "$PROJECT_ID" "$STATE_FILTER" "$ASSIGNEE_ID" "$LIMIT" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-issues.sh`

- [ ] **Step 4.6: Create `scripts/linear-get-issue.sh`**

```bash
#!/usr/bin/env bash
# linear-get-issue.sh — Fetch full details for a Linear issue.
# Usage: linear-get-issue.sh <ISSUE-ID> [--profile NAME]
# Output: single issue object with full field set
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

ISSUE_ID=""
PROFILE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) PROFILE_OVERRIDE="$2"; shift ;;
    -h|--help) echo "Usage: linear-get-issue.sh <ISSUE-ID> [--profile NAME]" >&2; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  ISSUE_ID="$1" ;;
  esac
  shift
done

if [[ -z "$ISSUE_ID" ]]; then
  echo "Usage: linear-get-issue.sh <ISSUE-ID> [--profile NAME]" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

linear_api "{ issue(id: \"$ISSUE_ID\") {
  id identifier title description priority url branchName
  state { name }
  assignee { name email }
  project { id name }
  labels { nodes { name } }
  parent { id identifier title }
  children { nodes { id identifier title } }
  relations { nodes { type relatedIssue { id identifier title } } }
} }" "$LINEAR_KEY_ENV" | jq '.data.issue // {"error":"Issue not found","identifier":"'"$ISSUE_ID"'"}'
```

Run: `chmod +x scripts/linear-get-issue.sh`

- [ ] **Step 4.7: Run tests to confirm they pass**

```bash
npx bats tests/test_linear_scripts.bats
```

Expected: all 8 tests pass.

- [ ] **Step 4.8: Commit**

```bash
git add scripts/linear-teams.sh scripts/linear-projects.sh \
        scripts/linear-issues.sh scripts/linear-get-issue.sh \
        tests/test_linear_scripts.bats
git commit -m "feat(scripts): add linear read scripts (teams, projects, issues, get-issue)"
```

---

## Task 5: Write Scripts

**Files:**
- Create: `scripts/linear-create-issue.sh`
- Create: `scripts/linear-update-issue.sh`
- Create: `scripts/linear-create-project.sh`
- Create: `scripts/linear-update-project.sh`
- Create: `scripts/linear-comment.sh`
- Modify: `tests/test_linear_scripts.bats`

- [ ] **Step 5.1: Write failing tests**

Append to `tests/test_linear_scripts.bats`:

```bash
# ---------------------------------------------------------------------------
# linear-create-issue.sh
# ---------------------------------------------------------------------------

@test "linear-create-issue.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-create-issue.sh" ]
}

@test "linear-create-issue.sh requires --title argument" {
  run bash -c "$REPO_ROOT/scripts/linear-create-issue.sh --profile apex 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--title"* ]]
}

@test "linear-create-issue.sh fails with unknown profile" {
  run bash -c "$REPO_ROOT/scripts/linear-create-issue.sh --title Test --profile nonexistent-xyz 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Profile not found"* ]]
}

# ---------------------------------------------------------------------------
# linear-update-issue.sh
# ---------------------------------------------------------------------------

@test "linear-update-issue.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-update-issue.sh" ]
}

@test "linear-update-issue.sh requires ISSUE-ID argument" {
  run bash -c "$REPO_ROOT/scripts/linear-update-issue.sh 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# linear-create-project.sh
# ---------------------------------------------------------------------------

@test "linear-create-project.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-create-project.sh" ]
}

@test "linear-create-project.sh requires --name argument" {
  run bash -c "$REPO_ROOT/scripts/linear-create-project.sh --profile apex 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--name"* ]]
}

# ---------------------------------------------------------------------------
# linear-update-project.sh
# ---------------------------------------------------------------------------

@test "linear-update-project.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-update-project.sh" ]
}

@test "linear-update-project.sh requires PROJECT-ID argument" {
  run bash -c "$REPO_ROOT/scripts/linear-update-project.sh 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# linear-comment.sh
# ---------------------------------------------------------------------------

@test "linear-comment.sh is executable" {
  [ -x "$REPO_ROOT/scripts/linear-comment.sh" ]
}

@test "linear-comment.sh requires ISSUE-ID and --body" {
  run bash -c "$REPO_ROOT/scripts/linear-comment.sh 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "linear-comment.sh requires --body when ISSUE-ID given" {
  run bash -c "$REPO_ROOT/scripts/linear-comment.sh DEV-1 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--body"* ]]
}
```

- [ ] **Step 5.2: Run tests to confirm they fail**

```bash
npx bats tests/test_linear_scripts.bats
```

Expected: 8 existing tests pass, 11 new tests FAIL.

- [ ] **Step 5.3: Create `scripts/linear-create-issue.sh`**

```bash
#!/usr/bin/env bash
# linear-create-issue.sh — Create a new Linear issue.
# Usage: linear-create-issue.sh --title TITLE
#                                [--team TEAM_NAME] [--description DESC]
#                                [--project PROJECT_NAME] [--priority 0-4]
#                                [--assignee NAME_OR_EMAIL]
#                                [--labels "Bug,Feature"] [--parent ISSUE-ID]
#                                [--profile NAME]
# Output: {success, issue: {id, identifier, title, url}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROFILE_OVERRIDE=""
TEAM_NAME=""
TITLE=""
DESCRIPTION=""
PROJECT_NAME=""
PRIORITY=""
ASSIGNEE=""
LABELS=""
PARENT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)     PROFILE_OVERRIDE="$2"; shift ;;
    --team)        TEAM_NAME="$2"; shift ;;
    --title)       TITLE="$2"; shift ;;
    --description) DESCRIPTION="$2"; shift ;;
    --project)     PROJECT_NAME="$2"; shift ;;
    --priority)    PRIORITY="$2"; shift ;;
    --assignee)    ASSIGNEE="$2"; shift ;;
    --labels)      LABELS="$2"; shift ;;
    --parent)      PARENT="$2"; shift ;;
    -h|--help)
      echo "Usage: linear-create-issue.sh --title TITLE [--team NAME] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]" >&2
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$TITLE" ]]; then
  echo "Error: --title is required" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

TEAM="${TEAM_NAME:-$DEFAULT_TEAM}"
if [[ -z "$TEAM" ]]; then
  echo '{"error":"No team specified and no default_team in profile"}' >&2
  exit 1
fi

TEAM_ID=$(linear_resolve_team_id "$TEAM" "$LINEAR_KEY_ENV")

PROJECT_ID=""
[[ -n "$PROJECT_NAME" ]] && PROJECT_ID=$(linear_resolve_project_id "$PROJECT_NAME" "$TEAM_ID" "$LINEAR_KEY_ENV")

ASSIGNEE_ID=""
[[ -n "$ASSIGNEE" ]] && ASSIGNEE_ID=$(linear_resolve_member_id "$ASSIGNEE" "$LINEAR_KEY_ENV")

LABEL_IDS="[]"
[[ -n "$LABELS" ]] && LABEL_IDS=$(linear_resolve_label_ids "$LABELS" "$TEAM_ID" "$LINEAR_KEY_ENV")

linear_create_issue "$TEAM_ID" "$TITLE" "$DESCRIPTION" "$PROJECT_ID" \
  "$PRIORITY" "$ASSIGNEE_ID" "$LABEL_IDS" "$PARENT" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-create-issue.sh`

- [ ] **Step 5.4: Create `scripts/linear-update-issue.sh`**

```bash
#!/usr/bin/env bash
# linear-update-issue.sh — Update fields on an existing Linear issue.
# Usage: linear-update-issue.sh <ISSUE-ID>
#                                [--title TITLE] [--description DESC]
#                                [--project PROJECT_NAME] [--priority 0-4]
#                                [--assignee NAME_OR_EMAIL]
#                                [--labels "Bug,Feature"] [--parent ISSUE-ID]
#                                [--profile NAME]
# Output: {success, issue: {id, identifier, title, url}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

ISSUE_ID=""
PROFILE_OVERRIDE=""
TITLE=""
DESCRIPTION=""
PROJECT_NAME=""
PRIORITY=""
ASSIGNEE=""
LABELS=""
PARENT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)     PROFILE_OVERRIDE="$2"; shift ;;
    --title)       TITLE="$2"; shift ;;
    --description) DESCRIPTION="$2"; shift ;;
    --project)     PROJECT_NAME="$2"; shift ;;
    --priority)    PRIORITY="$2"; shift ;;
    --assignee)    ASSIGNEE="$2"; shift ;;
    --labels)      LABELS="$2"; shift ;;
    --parent)      PARENT="$2"; shift ;;
    -h|--help)
      echo "Usage: linear-update-issue.sh <ISSUE-ID> [--title TITLE] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]" >&2
      exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  ISSUE_ID="$1" ;;
  esac
  shift
done

if [[ -z "$ISSUE_ID" ]]; then
  echo "Usage: linear-update-issue.sh <ISSUE-ID> [options]" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

PROJECT_ID=""
if [[ -n "$PROJECT_NAME" ]]; then
  TEAM_ID=$(linear_resolve_team_id "${DEFAULT_TEAM:-}" "$LINEAR_KEY_ENV") || true
  PROJECT_ID=$(linear_resolve_project_id "$PROJECT_NAME" "${TEAM_ID:-}" "$LINEAR_KEY_ENV")
fi

ASSIGNEE_ID=""
[[ -n "$ASSIGNEE" ]] && ASSIGNEE_ID=$(linear_resolve_member_id "$ASSIGNEE" "$LINEAR_KEY_ENV")

LABEL_IDS=""
if [[ -n "$LABELS" ]]; then
  TEAM_ID=$(linear_resolve_team_id "${DEFAULT_TEAM:-}" "$LINEAR_KEY_ENV") || true
  LABEL_IDS=$(linear_resolve_label_ids "$LABELS" "${TEAM_ID:-}" "$LINEAR_KEY_ENV")
fi

linear_update_issue "$ISSUE_ID" "$TITLE" "$DESCRIPTION" "$PROJECT_ID" \
  "$PRIORITY" "$ASSIGNEE_ID" "$LABEL_IDS" "$PARENT" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-update-issue.sh`

- [ ] **Step 5.5: Create `scripts/linear-create-project.sh`**

```bash
#!/usr/bin/env bash
# linear-create-project.sh — Create a new Linear project.
# Usage: linear-create-project.sh --name NAME
#                                   [--team TEAM_NAME] [--description DESC]
#                                   [--state backlog|planned|started|paused|completed|cancelled]
#                                   [--profile NAME]
# Output: {success, project: {id, name, state, url}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROFILE_OVERRIDE=""
TEAM_NAME=""
NAME=""
DESCRIPTION=""
STATE="backlog"

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)     PROFILE_OVERRIDE="$2"; shift ;;
    --team)        TEAM_NAME="$2"; shift ;;
    --name)        NAME="$2"; shift ;;
    --description) DESCRIPTION="$2"; shift ;;
    --state)       STATE="$2"; shift ;;
    -h|--help)
      echo "Usage: linear-create-project.sh --name NAME [--team NAME] [--description DESC] [--state STATE] [--profile NAME]" >&2
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "$NAME" ]]; then
  echo "Error: --name is required" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

TEAM="${TEAM_NAME:-$DEFAULT_TEAM}"
if [[ -z "$TEAM" ]]; then
  echo '{"error":"No team specified and no default_team in profile"}' >&2
  exit 1
fi

TEAM_ID=$(linear_resolve_team_id "$TEAM" "$LINEAR_KEY_ENV")
linear_create_project "$TEAM_ID" "$NAME" "$DESCRIPTION" "$STATE" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-create-project.sh`

- [ ] **Step 5.6: Create `scripts/linear-update-project.sh`**

```bash
#!/usr/bin/env bash
# linear-update-project.sh — Update an existing Linear project.
# Usage: linear-update-project.sh <PROJECT-ID-OR-NAME>
#                                   [--name NAME] [--description DESC]
#                                   [--state STATE] [--profile NAME]
# Output: {success, project: {id, name, state, url}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

PROJECT_ARG=""
PROFILE_OVERRIDE=""
NAME=""
DESCRIPTION=""
STATE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)     PROFILE_OVERRIDE="$2"; shift ;;
    --name)        NAME="$2"; shift ;;
    --description) DESCRIPTION="$2"; shift ;;
    --state)       STATE="$2"; shift ;;
    -h|--help)
      echo "Usage: linear-update-project.sh <PROJECT-ID-OR-NAME> [--name NAME] [--description DESC] [--state STATE] [--profile NAME]" >&2
      exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  PROJECT_ARG="$1" ;;
  esac
  shift
done

if [[ -z "$PROJECT_ARG" ]]; then
  echo "Usage: linear-update-project.sh <PROJECT-ID-OR-NAME> [options]" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"

# 36-char UUID passthrough, otherwise resolve by name
PROJECT_ID=""
if [[ "${#PROJECT_ARG}" -eq 36 && "$PROJECT_ARG" =~ ^[0-9a-f-]+$ ]]; then
  PROJECT_ID="$PROJECT_ARG"
else
  TEAM_ID=$(linear_resolve_team_id "${DEFAULT_TEAM:-}" "$LINEAR_KEY_ENV") || true
  PROJECT_ID=$(linear_resolve_project_id "$PROJECT_ARG" "${TEAM_ID:-}" "$LINEAR_KEY_ENV")
fi

linear_update_project "$PROJECT_ID" "$NAME" "$DESCRIPTION" "$STATE" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-update-project.sh`

- [ ] **Step 5.7: Create `scripts/linear-comment.sh`**

```bash
#!/usr/bin/env bash
# linear-comment.sh — Add a comment to a Linear issue.
# Usage: linear-comment.sh <ISSUE-ID> --body TEXT [--profile NAME]
# Output: {success, comment: {id, body, createdAt}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOUSTON_DIR/pipeline/linear.sh"
source "$HOUSTON_DIR/pipeline/lib/parse-profile.sh"
source "$HOUSTON_DIR/pipeline/lib/load-profile.sh"

ISSUE_ID=""
BODY=""
PROFILE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) PROFILE_OVERRIDE="$2"; shift ;;
    --body)    BODY="$2"; shift ;;
    -h|--help) echo "Usage: linear-comment.sh <ISSUE-ID> --body TEXT [--profile NAME]" >&2; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  ISSUE_ID="$1" ;;
  esac
  shift
done

if [[ -z "$ISSUE_ID" ]]; then
  echo "Usage: linear-comment.sh <ISSUE-ID> --body TEXT [--profile NAME]" >&2
  exit 1
fi

if [[ -z "$BODY" ]]; then
  echo "Error: --body is required" >&2
  exit 1
fi

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"
linear_add_comment "$ISSUE_ID" "$BODY" "$LINEAR_KEY_ENV"
```

Run: `chmod +x scripts/linear-comment.sh`

- [ ] **Step 5.8: Run all script tests**

```bash
npx bats tests/test_linear_scripts.bats
```

Expected: all 19 tests pass.

- [ ] **Step 5.9: Commit**

```bash
git add scripts/linear-create-issue.sh scripts/linear-update-issue.sh \
        scripts/linear-create-project.sh scripts/linear-update-project.sh \
        scripts/linear-comment.sh tests/test_linear_scripts.bats
git commit -m "feat(scripts): add linear write scripts (create/update issue, project, comment)"
```

---

## Task 6: Skill Command Files

**Files:**
- Create: `commands/linear-teams.md`
- Create: `commands/linear-projects.md`
- Create: `commands/linear-issues.md`
- Create: `commands/linear-get-issue.md`
- Create: `commands/linear-create-issue.md`
- Create: `commands/linear-update-issue.md`
- Create: `commands/linear-create-project.md`
- Create: `commands/linear-update-project.md`
- Create: `commands/linear-comment.md`

- [ ] **Step 6.1: Create `commands/linear-teams.md`**

```markdown
---
description: "List all Linear teams in the workspace"
argument-hint: "[--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-teams.sh $ARGUMENTS` and display the results.

Present teams as a table: name and key (e.g. "Development — DEV").

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.2: Create `commands/linear-projects.md`**

```markdown
---
description: "List Linear projects in a team"
argument-hint: "[--team TEAM_NAME] [--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-projects.sh $ARGUMENTS` and display the results.

If no `--team` is given, the script uses the default team from the active profile.

Present projects as a list: name, state, and URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.3: Create `commands/linear-issues.md`**

```markdown
---
description: "List Linear issues with optional filters"
argument-hint: "[--project NAME_OR_UUID] [--team NAME] [--state STATE] [--assignee NAME_OR_EMAIL] [--limit N] [--profile NAME]"
---

If `--project` is not given:
1. Run `$HOUSTON_DIR/scripts/linear-projects.sh` to list available projects.
2. Present the list and ask the user to select one.
3. Run `$HOUSTON_DIR/scripts/linear-issues.sh --project <uuid-from-step-2> $ARGUMENTS`.

If `--project` is given, run `$HOUSTON_DIR/scripts/linear-issues.sh $ARGUMENTS` directly.

Present issues as a table: identifier, title, state, assignee, priority label (none/urgent/high/medium/low).

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.4: Create `commands/linear-get-issue.md`**

```markdown
---
description: "Fetch full details for a Linear issue"
argument-hint: "<ISSUE-ID> [--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-get-issue.sh $ARGUMENTS` and display the results.

Present as a structured card:
- Title, identifier, URL
- State, priority, assignee
- Project, labels
- Description (truncated to 500 chars if long)
- Parent / children if present

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.5: Create `commands/linear-create-issue.md`**

```markdown
---
description: "Create a new Linear issue"
argument-hint: "--title TITLE [--team NAME] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]"
---

Confirm the fields with the user before creating, then run:
`$HOUSTON_DIR/scripts/linear-create-issue.sh $ARGUMENTS`

On success, display the issue identifier and URL from the JSON response.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.6: Create `commands/linear-update-issue.md`**

```markdown
---
description: "Update fields on an existing Linear issue"
argument-hint: "<ISSUE-ID> [--title TITLE] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]"
---

1. Run `$HOUSTON_DIR/scripts/linear-get-issue.sh <ISSUE-ID>` to show the current state.
2. Confirm the intended changes with the user.
3. Run `$HOUSTON_DIR/scripts/linear-update-issue.sh $ARGUMENTS`.

On success, display the updated issue URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.7: Create `commands/linear-create-project.md`**

```markdown
---
description: "Create a new Linear project"
argument-hint: "--name NAME [--team TEAM_NAME] [--description DESC] [--state STATE] [--profile NAME]"
---

Confirm the project name and team with the user, then run:
`$HOUSTON_DIR/scripts/linear-create-project.sh $ARGUMENTS`

On success, display the project name and URL from the JSON response.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.8: Create `commands/linear-update-project.md`**

```markdown
---
description: "Update an existing Linear project"
argument-hint: "<PROJECT-ID-OR-NAME> [--name NAME] [--description DESC] [--state STATE] [--profile NAME]"
---

If no project is specified:
1. Run `$HOUSTON_DIR/scripts/linear-projects.sh` to list available projects.
2. Present the list and ask the user to select one.
3. Run `$HOUSTON_DIR/scripts/linear-update-project.sh <selected-id> $ARGUMENTS`.

If a project name or ID is provided, run `$HOUSTON_DIR/scripts/linear-update-project.sh $ARGUMENTS` directly.

On success, display the updated project URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.9: Create `commands/linear-comment.md`**

```markdown
---
description: "Add a comment to a Linear issue"
argument-hint: "<ISSUE-ID> --body TEXT [--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-comment.sh $ARGUMENTS` and display the result.

On success, confirm the comment was posted with its ID.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
```

- [ ] **Step 6.10: Commit**

```bash
git add commands/linear-teams.md commands/linear-projects.md \
        commands/linear-issues.md commands/linear-get-issue.md \
        commands/linear-create-issue.md commands/linear-update-issue.md \
        commands/linear-create-project.md commands/linear-update-project.md \
        commands/linear-comment.md
git commit -m "feat(commands): add linear skill definitions for all 9 operations"
```

---

## Final Verification

- [ ] **Run full test suite**

```bash
npx bats tests/test_parse_profile.bats tests/test_linear.bats \
         tests/test_load_profile.bats tests/test_linear_scripts.bats
```

Expected: all tests pass.

- [ ] **Smoke test live API (apex profile)**

```bash
scripts/linear-teams.sh --profile apex
scripts/linear-projects.sh --profile apex
scripts/linear-issues.sh --profile apex --limit 3
```

Expected: valid JSON arrays with real Skyner Group data.
