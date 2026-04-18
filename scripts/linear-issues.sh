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
  TEAM_ID=$(linear_resolve_team_id "$TEAM" "$LINEAR_KEY_ENV") || {
    echo '{"error":"Team not found: '"$TEAM"'"}' >&2
    exit 1
  }
fi

if [[ -n "$PROJECT_ARG" ]]; then
  if [[ "${#PROJECT_ARG}" -eq 36 && "$PROJECT_ARG" =~ ^[0-9a-f-]+$ ]]; then
    PROJECT_ID="$PROJECT_ARG"
  else
    PROJECT_ID=$(linear_resolve_project_id "$PROJECT_ARG" "$TEAM_ID" "$LINEAR_KEY_ENV")
  fi
fi

if [[ -n "$ASSIGNEE" ]]; then
  ASSIGNEE_ID=$(linear_resolve_member_id "$ASSIGNEE" "$LINEAR_KEY_ENV") || {
    echo '{"error":"Assignee not found: '"$ASSIGNEE"'"}' >&2
    exit 1
  }
fi

linear_list_issues "$TEAM_ID" "$PROJECT_ID" "$STATE_FILTER" "$ASSIGNEE_ID" "$LIMIT" "$LINEAR_KEY_ENV"
