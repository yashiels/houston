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
