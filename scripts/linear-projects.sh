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
    --profile) PROFILE_OVERRIDE="${2:-}"; shift ;;
    --team)    TEAM_NAME="${2:-}"; shift ;;
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
