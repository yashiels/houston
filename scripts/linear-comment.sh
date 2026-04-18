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
