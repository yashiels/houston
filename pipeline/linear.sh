#!/usr/bin/env bash
# linear.sh — Linear API integration for Houston
# Source this file to use: source pipeline/linear.sh
# Requires: curl, jq
#
# All functions take an optional api-key-env parameter that names the
# environment variable holding the Linear API key (defaults to LINEAR_API_KEY).
#
# Workspace keys:
#   LINEAR_API_KEY        — Stitch workspace
#   SKYNER_LINEAR_API_KEY — Skyner workspace

# Don't set -e since this is sourced — let callers handle errors

# ---------------------------------------------------------------------------
# linear_api <graphql-query> [api-key-env-var]
# Low-level GraphQL request to Linear. Returns JSON response on stdout.
# ---------------------------------------------------------------------------
linear_api() {
  local query="$1"
  local key_env="${2:-LINEAR_API_KEY}"
  local api_key="${!key_env}"

  if [ -z "$api_key" ]; then
    echo '{"error":"No API key found in env var '"$key_env"'"}' >&2
    return 1
  fi

  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $api_key" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$query" | jq -Rs .)}"
}

# ---------------------------------------------------------------------------
# linear_get_issue <issue-identifier> [api-key-env]
# Fetch a Linear issue by its identifier (e.g. "SWITCH-167").
# Returns JSON with id, title, description, state, branchName, url, parent,
# children, and relations.
# ---------------------------------------------------------------------------
linear_get_issue() {
  local identifier="$1"
  local key_env="${2:-LINEAR_API_KEY}"

  local query
  query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$identifier" } }) {
    nodes {
      id
      identifier
      title
      description
      url
      branchName
      state { name }
      parent { id identifier }
      children {
        nodes { id identifier title }
      }
      relations {
        nodes {
          type
          relatedIssue { id identifier title }
        }
      }
    }
  }
}
GRAPHQL
  )

  linear_api "$query" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_update_status <issue-identifier> <status-name> [api-key-env]
# Update an issue's workflow state. Status names: "Todo", "In Progress",
# "In Review", "Done", etc.
# First resolves the issue's team, then finds the matching workflow state ID,
# then updates the issue.
# ---------------------------------------------------------------------------
linear_update_status() {
  local identifier="$1"
  local status_name="$2"
  local key_env="${3:-LINEAR_API_KEY}"

  # Step 1: Get the issue's internal ID and team ID
  local issue_query
  issue_query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$identifier" } }) {
    nodes {
      id
      team { id }
    }
  }
}
GRAPHQL
  )

  local issue_result
  issue_result=$(linear_api "$issue_query" "$key_env")

  local issue_id team_id
  issue_id=$(echo "$issue_result" | jq -r '.data.issueSearch.nodes[0].id // empty')
  team_id=$(echo "$issue_result" | jq -r '.data.issueSearch.nodes[0].team.id // empty')

  if [ -z "$issue_id" ] || [ -z "$team_id" ]; then
    echo '{"error":"Issue not found","identifier":"'"$identifier"'"}' >&2
    return 1
  fi

  # Step 2: Find the workflow state ID for the given status name
  local state_query
  state_query=$(cat <<GRAPHQL
query {
  workflowStates(filter: { team: { id: { eq: "$team_id" } }, name: { eq: "$status_name" } }) {
    nodes {
      id
      name
    }
  }
}
GRAPHQL
  )

  local state_result
  state_result=$(linear_api "$state_query" "$key_env")

  local state_id
  state_id=$(echo "$state_result" | jq -r '.data.workflowStates.nodes[0].id // empty')

  if [ -z "$state_id" ]; then
    echo '{"error":"Workflow state not found","status":"'"$status_name"'","team_id":"'"$team_id"'"}' >&2
    return 1
  fi

  # Step 3: Update the issue
  local update_query
  update_query=$(cat <<GRAPHQL
mutation {
  issueUpdate(id: "$issue_id", input: { stateId: "$state_id" }) {
    success
    issue {
      id
      identifier
      state { name }
    }
  }
}
GRAPHQL
  )

  linear_api "$update_query" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_create_sub_issue <parent-identifier> <title> <description> <team-id> [api-key-env]
# Create a child issue linked to a parent.
# ---------------------------------------------------------------------------
linear_create_sub_issue() {
  local parent_identifier="$1"
  local title="$2"
  local description="$3"
  local team_id="$4"
  local key_env="${5:-LINEAR_API_KEY}"

  # Resolve parent's internal ID
  local parent_query
  parent_query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$parent_identifier" } }) {
    nodes { id }
  }
}
GRAPHQL
  )

  local parent_result
  parent_result=$(linear_api "$parent_query" "$key_env")

  local parent_id
  parent_id=$(echo "$parent_result" | jq -r '.data.issueSearch.nodes[0].id // empty')

  if [ -z "$parent_id" ]; then
    echo '{"error":"Parent issue not found","identifier":"'"$parent_identifier"'"}' >&2
    return 1
  fi

  # Escape title and description for GraphQL string embedding
  local escaped_title escaped_desc
  escaped_title=$(echo "$title" | jq -Rs . | sed 's/^"//;s/"$//')
  escaped_desc=$(echo "$description" | jq -Rs . | sed 's/^"//;s/"$//')

  local create_query
  create_query=$(cat <<GRAPHQL
mutation {
  issueCreate(input: {
    teamId: "$team_id"
    parentId: "$parent_id"
    title: "$escaped_title"
    description: "$escaped_desc"
  }) {
    success
    issue {
      id
      identifier
      title
      url
      parent { id identifier }
    }
  }
}
GRAPHQL
  )

  linear_api "$create_query" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_add_comment <issue-identifier> <body> [api-key-env]
# Add a comment to an issue.
# ---------------------------------------------------------------------------
linear_add_comment() {
  local identifier="$1"
  local body="$2"
  local key_env="${3:-LINEAR_API_KEY}"

  # Resolve internal ID
  local issue_query
  issue_query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$identifier" } }) {
    nodes { id }
  }
}
GRAPHQL
  )

  local issue_result
  issue_result=$(linear_api "$issue_query" "$key_env")

  local issue_id
  issue_id=$(echo "$issue_result" | jq -r '.data.issueSearch.nodes[0].id // empty')

  if [ -z "$issue_id" ]; then
    echo '{"error":"Issue not found","identifier":"'"$identifier"'"}' >&2
    return 1
  fi

  local escaped_body
  escaped_body=$(echo "$body" | jq -Rs . | sed 's/^"//;s/"$//')

  local comment_query
  comment_query=$(cat <<GRAPHQL
mutation {
  commentCreate(input: {
    issueId: "$issue_id"
    body: "$escaped_body"
  }) {
    success
    comment {
      id
      body
      createdAt
    }
  }
}
GRAPHQL
  )

  linear_api "$comment_query" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_attach_url <issue-identifier> <url> <title> [api-key-env]
# Attach a URL (e.g. a PR link) to an issue.
# ---------------------------------------------------------------------------
linear_attach_url() {
  local identifier="$1"
  local url="$2"
  local title="$3"
  local key_env="${4:-LINEAR_API_KEY}"

  # Resolve internal ID
  local issue_query
  issue_query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$identifier" } }) {
    nodes { id }
  }
}
GRAPHQL
  )

  local issue_result
  issue_result=$(linear_api "$issue_query" "$key_env")

  local issue_id
  issue_id=$(echo "$issue_result" | jq -r '.data.issueSearch.nodes[0].id // empty')

  if [ -z "$issue_id" ]; then
    echo '{"error":"Issue not found","identifier":"'"$identifier"'"}' >&2
    return 1
  fi

  local escaped_title
  escaped_title=$(echo "$title" | jq -Rs . | sed 's/^"//;s/"$//')

  local attach_query
  attach_query=$(cat <<GRAPHQL
mutation {
  attachmentCreate(input: {
    issueId: "$issue_id"
    url: "$url"
    title: "$escaped_title"
  }) {
    success
    attachment {
      id
      url
      title
    }
  }
}
GRAPHQL
  )

  linear_api "$attach_query" "$key_env"
}

# ---------------------------------------------------------------------------
# linear_find_ticket <identifier> [api-key-env-1] [api-key-env-2] ...
# Try to find a ticket across multiple Linear workspaces. Tries each API key
# env var in order. Returns the issue JSON with .matched_key_env set.
#
# Defaults to trying LINEAR_API_KEY then SKYNER_LINEAR_API_KEY.
# ---------------------------------------------------------------------------
linear_find_ticket() {
  local identifier="$1"
  shift
  local keys=("${@:-LINEAR_API_KEY SKYNER_LINEAR_API_KEY}")

  # If no extra args were provided, the default is a single string — split it
  if [ "$#" -eq 0 ]; then
    keys=(LINEAR_API_KEY SKYNER_LINEAR_API_KEY)
  fi

  for key_env in "${keys[@]}"; do
    if [ -n "${!key_env:-}" ]; then
      local result
      result=$(linear_get_issue "$identifier" "$key_env")
      local count
      count=$(echo "$result" | jq -r '.data.issueSearch.nodes | length' 2>/dev/null)
      if [ "$count" != "0" ] && [ "$count" != "null" ] && [ -n "$count" ]; then
        echo "$result" | jq --arg key "$key_env" '.matched_key_env = $key'
        return 0
      fi
    fi
  done

  echo '{"error":"Ticket not found in any workspace","identifier":"'"$identifier"'"}' >&2
  return 1
}

# ---------------------------------------------------------------------------
# linear_get_dependencies <issue-identifier> [api-key-env]
# Get blocking/blocked-by relations for an issue. Returns a JSON array of
# objects with relation type and related issue identifier.
# ---------------------------------------------------------------------------
linear_get_dependencies() {
  local identifier="$1"
  local key_env="${2:-LINEAR_API_KEY}"

  local query
  query=$(cat <<GRAPHQL
query {
  issueSearch(filter: { identifier: { eq: "$identifier" } }) {
    nodes {
      id
      identifier
      relations {
        nodes {
          type
          relatedIssue {
            id
            identifier
            title
            state { name }
          }
        }
      }
    }
  }
}
GRAPHQL
  )

  local result
  result=$(linear_api "$query" "$key_env")

  # Extract just the relations array, filtering to blocking/blocked-by types
  echo "$result" | jq '
    .data.issueSearch.nodes[0].relations.nodes
    // []
    | map(select(.type == "blocks" or .type == "blocked_by" or .type == "depends_on" or .type == "is_blocked_by"))
    | map({
        type: .type,
        identifier: .relatedIssue.identifier,
        title: .relatedIssue.title,
        state: .relatedIssue.state.name
      })
  '
}
