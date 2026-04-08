#!/usr/bin/env bash
# check-comments.sh — Check for unresolved review comments on a PR/MR.
#
# Usage: ./scripts/check-comments.sh [--pr <number>] [--branch <name>]
#
# If no PR number given, detects from current branch.
# Auto-detects platform (GitHub/GitLab) from git remote.
# Outputs actionable comments as JSON to stdout; messages to stderr.

set -euo pipefail

# ─── Parse arguments ───

PR_NUMBER=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --pr)     PR_NUMBER="$2"; shift ;;
    --branch) BRANCH="$2"; shift ;;
    -h|--help)
      echo "Usage: ./scripts/check-comments.sh [--pr <number>] [--branch <name>]" >&2
      exit 0
      ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

# ─── Detect platform ───

REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
PLATFORM="unknown"

if [[ "$REMOTE_URL" == *"github"* ]]; then
  PLATFORM="github"
elif [[ "$REMOTE_URL" == *"gitlab"* ]]; then
  PLATFORM="gitlab"
fi

if [[ "$PLATFORM" == "unknown" ]]; then
  echo "ERROR: Cannot detect platform from remote: $REMOTE_URL" >&2
  exit 1
fi

echo "Platform: $PLATFORM" >&2

# ─── Resolve branch ───

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || echo "")"
fi

if [[ -z "$BRANCH" ]]; then
  echo "ERROR: Cannot determine current branch" >&2
  exit 1
fi

echo "Branch: $BRANCH" >&2

# ─── Bot and praise filters ───

BOT_PATTERNS="coderabbit|dependabot|renovate|github-actions|gitlab-bot|mergify|codecov|sonarqube|snyk|greenkeeper"
PRAISE_PATTERNS="^(lgtm|looks good|nice|great|awesome|ship it|:shipit:|:lgtm:|:thumbsup:|\\+1)[[:space:]!.]*$"

is_bot() {
  local author="$1"
  echo "$author" | grep -qiE "$BOT_PATTERNS"
}

is_praise() {
  local body="$1"
  local trimmed
  trimmed="$(echo "$body" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
  echo "$trimmed" | grep -qiE "$PRAISE_PATTERNS"
}

# ─── GitHub: fetch comments ───

github_fetch_comments() {
  local pr="$1"

  # Extract owner/repo from remote
  local owner_repo
  owner_repo="$(echo "$REMOTE_URL" | sed -E 's#(https?://[^/]+/|git@[^:]+:)##' | sed 's/\.git$//')"

  echo "Fetching review comments for PR #${pr} on ${owner_repo}..." >&2

  local inline_comments top_level_comments all_comments

  # Fetch inline/diff review comments
  inline_comments="$(gh api "repos/${owner_repo}/pulls/${pr}/comments" --paginate 2>/dev/null | jq -c '
    [.[] | {
      author: .user.login,
      file: .path,
      line: (.line // .original_line // null),
      body: .body,
      type: "inline",
      resolved: false,
      url: .html_url
    }]
  ' 2>/dev/null || echo '[]')"

  # Fetch top-level PR comments
  top_level_comments="$(gh pr view "$pr" --json comments 2>/dev/null | jq -c '
    [.comments[] | {
      author: .author.login,
      file: null,
      line: null,
      body: .body,
      type: "top-level",
      resolved: false,
      url: ""
    }]
  ' 2>/dev/null || echo '[]')"

  # Fetch review threads to check resolved status
  local resolved_bodies
  resolved_bodies="$(gh api "repos/${owner_repo}/pulls/${pr}/reviews" --paginate 2>/dev/null | jq -r '
    [.[] | select(.state == "DISMISSED" or .state == "APPROVED") | .body] | .[]
  ' 2>/dev/null || echo "")"

  # Merge inline + top-level
  all_comments="$(jq -sc '.[0] + .[1]' <(echo "$inline_comments") <(echo "$top_level_comments"))"

  echo "$all_comments"
}

# ─── GitLab: fetch comments ───

gitlab_fetch_comments() {
  local mr="$1"

  echo "Fetching discussions for MR !${mr}..." >&2

  local all_comments

  # Fetch all discussions (includes inline and top-level)
  all_comments="$(glab api "projects/:id/merge_requests/${mr}/discussions" --paginate 2>/dev/null | jq -c '
    [.[] | . as $disc |
      if .notes[0].resolvable == true then
        {
          author: .notes[0].author.username,
          file: (.notes[0].position.new_path // .notes[0].position.old_path // null),
          line: (.notes[0].position.new_line // .notes[0].position.old_line // null),
          body: .notes[0].body,
          type: (if .notes[0].position then "inline" else "top-level" end),
          resolved: ($disc.resolved // false),
          url: (.notes[0].web_url // "")
        }
      else
        {
          author: .notes[0].author.username,
          file: null,
          line: null,
          body: .notes[0].body,
          type: "top-level",
          resolved: false,
          url: (.notes[0].web_url // "")
        }
      end
    ] | [.[] | select(.body != null)]
  ' 2>/dev/null || echo '[]')"

  echo "$all_comments"
}

# ─── Resolve PR/MR number ───

if [[ -z "$PR_NUMBER" ]]; then
  echo "Detecting PR/MR for branch '$BRANCH'..." >&2

  if [[ "$PLATFORM" == "github" ]]; then
    PR_NUMBER="$(gh pr view "$BRANCH" --json number -q .number 2>/dev/null || echo "")"
  elif [[ "$PLATFORM" == "gitlab" ]]; then
    PR_NUMBER="$(glab mr view "$BRANCH" --output json 2>/dev/null | jq -r '.iid' 2>/dev/null || echo "")"
  fi

  if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: No open PR/MR found for branch '$BRANCH'" >&2
    exit 1
  fi
fi

echo "PR/MR number: $PR_NUMBER" >&2

# ─── Fetch comments ───

RAW_COMMENTS=""
if [[ "$PLATFORM" == "github" ]]; then
  RAW_COMMENTS="$(github_fetch_comments "$PR_NUMBER")"
elif [[ "$PLATFORM" == "gitlab" ]]; then
  RAW_COMMENTS="$(gitlab_fetch_comments "$PR_NUMBER")"
fi

if [[ -z "$RAW_COMMENTS" || "$RAW_COMMENTS" == "[]" ]]; then
  jq -n \
    --arg pr "$PR_NUMBER" \
    --arg platform "$PLATFORM" \
    '{
      pr_number: ($pr | tonumber),
      platform: $platform,
      total_comments: 0,
      actionable: 0,
      comments: []
    }'
  exit 0
fi

TOTAL_COMMENTS="$(echo "$RAW_COMMENTS" | jq 'length')"

# ─── Filter comments ───

ACTIONABLE_COMMENTS="$(echo "$RAW_COMMENTS" | jq -c --arg bots "$BOT_PATTERNS" --arg praise "$PRAISE_PATTERNS" '
  [.[] |
    select(.resolved != true) |
    select(.author | test($bots; "i") | not) |
    select(
      (.body | gsub("^\\s+|\\s+$"; "") | ascii_downcase) as $trimmed |
      ($trimmed | test($praise; "i")) | not
    )
  ]
')"

ACTIONABLE_COUNT="$(echo "$ACTIONABLE_COMMENTS" | jq 'length')"

echo "Total comments: $TOTAL_COMMENTS, actionable: $ACTIONABLE_COUNT" >&2

# ─── Output JSON ───

jq -n \
  --argjson pr "$PR_NUMBER" \
  --arg platform "$PLATFORM" \
  --argjson total "$TOTAL_COMMENTS" \
  --argjson actionable "$ACTIONABLE_COUNT" \
  --argjson comments "$ACTIONABLE_COMMENTS" \
  '{
    pr_number: $pr,
    platform: $platform,
    total_comments: $total,
    actionable: $actionable,
    comments: $comments
  }'
