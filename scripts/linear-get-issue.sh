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
