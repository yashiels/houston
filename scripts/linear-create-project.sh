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
    --profile)     PROFILE_OVERRIDE="${2:-}"; shift ;;
    --team)        TEAM_NAME="${2:-}"; shift ;;
    --name)        NAME="${2:-}"; shift ;;
    --description) DESCRIPTION="${2:-}"; shift ;;
    --state)       STATE="${2:-}"; shift ;;
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
