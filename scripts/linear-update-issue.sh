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
