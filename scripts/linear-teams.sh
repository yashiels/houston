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
    --profile) PROFILE_OVERRIDE="${2:-}"; shift ;;
    -h|--help) echo "Usage: linear-teams.sh [--profile NAME]" >&2; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

_load_linear_context "$PROFILE_OVERRIDE" "$HOUSTON_DIR"
linear_list_teams "$LINEAR_KEY_ENV"
