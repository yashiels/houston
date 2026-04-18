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

PROJECT_ID=""
if [[ "${#PROJECT_ARG}" -eq 36 && "$PROJECT_ARG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  PROJECT_ID="$PROJECT_ARG"
else
  TEAM_ID=$(linear_resolve_team_id "${DEFAULT_TEAM:-}" "$LINEAR_KEY_ENV") || true
  PROJECT_ID=$(linear_resolve_project_id "$PROJECT_ARG" "${TEAM_ID:-}" "$LINEAR_KEY_ENV")
fi

linear_update_project "$PROJECT_ID" "$NAME" "$DESCRIPTION" "$STATE" "$LINEAR_KEY_ENV"
