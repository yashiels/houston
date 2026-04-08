#!/usr/bin/env bash
# create-pr.sh — Create a PR (GitHub) or MR (GitLab) with correct format
# Usage: ./scripts/create-pr.sh <ticket-id> [--type feat|fix|chore] [--area <area>] [--title <title>] [--bullet1 <text>] [--bullet2 <text>]
#
# Auto-detects platform (GitHub/GitLab) from git remote.
# Loads reviewers from Houston profile context.
# Enables: squash commits, delete source branch, auto-merge.
#
# Title format: type(area): short description [TICKET-ID]
# Body format: 2 bullet points (CodeRabbit handles the rest)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Parse arguments ───

TICKET_ID=""
PR_TYPE="feat"
AREA=""
TITLE=""
BULLET1=""
BULLET2=""
BRANCH=""
RUN_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --type)    PR_TYPE="$2"; shift ;;
    --area)    AREA="$2"; shift ;;
    --title)   TITLE="$2"; shift ;;
    --bullet1) BULLET1="$2"; shift ;;
    --bullet2) BULLET2="$2"; shift ;;
    --branch)  BRANCH="$2"; shift ;;
    --run-dir) RUN_DIR="$2"; shift ;;
    -*)        echo "Unknown option: $1" >&2; exit 1 ;;
    *)         TICKET_ID="$1" ;;
  esac
  shift
done

if [[ -z "$TICKET_ID" ]]; then
  echo "Usage: create-pr.sh <ticket-id> [--type feat|fix|chore] [--area area] [--title title] [--bullet1 text] [--bullet2 text]" >&2
  exit 1
fi

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

# ─── Resolve branch ───

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null)"
fi

if [[ -z "$BRANCH" || "$BRANCH" =~ ^(main|master|develop)$ ]]; then
  echo "ERROR: Must be on a feature branch, not '$BRANCH'" >&2
  exit 1
fi

# ─── Build title and body from prd.json if available ───

if [[ -z "$RUN_DIR" ]]; then
  RUN_DIR="$HOME/.houston/runs/$TICKET_ID"
fi

if [[ -z "$TITLE" && -f "$RUN_DIR/prd.json" ]]; then
  TITLE="$(jq -r '.title // empty' "$RUN_DIR/prd.json")"
fi

# Fallback: derive title from git log
if [[ -z "$TITLE" ]]; then
  # Use first commit subject as title hint, strip any existing type prefix
  TITLE="$(git log main..HEAD --format='%s' --reverse 2>/dev/null | head -1 | sed -E 's/^[a-z]+\([^)]*\): //' | sed -E "s/ *\[${TICKET_ID}\]//" || echo "")"
fi
if [[ -z "$TITLE" ]]; then
  TITLE="$TICKET_ID implementation"
fi

if [[ -z "$AREA" && -f "$RUN_DIR/prd.json" ]]; then
  # Extract area from first phase name, lowercased
  AREA="$(jq -r '.phases[0].name // empty' "$RUN_DIR/prd.json" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | head -c 25)"
fi

# Fallback: derive area from first commit's conventional commit scope
if [[ -z "$AREA" ]]; then
  AREA="$(git log main..HEAD --format='%s' --reverse 2>/dev/null | head -1 | grep -oE '^\w+\(([^)]+)\)' | sed -E 's/^\w+\(//;s/\)//' || echo "")"
fi
if [[ -z "$AREA" ]]; then
  AREA="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')"
fi

if [[ -z "$BULLET1" && -f "$RUN_DIR/prd.json" ]]; then
  BULLET1="$(jq -r '.phases[0].description // empty' "$RUN_DIR/prd.json")"
fi

# Fallback: derive bullets from git log
if [[ -z "$BULLET1" ]]; then
  BULLET1="$(git log main..HEAD --format='%s' --reverse 2>/dev/null | head -1 || echo "Implemented $TICKET_ID")"
fi

if [[ -z "$BULLET2" && -f "$RUN_DIR/prd.json" ]]; then
  BULLET2="$(jq -r 'if (.phases | length) > 1 then .phases[1].description else empty end' "$RUN_DIR/prd.json")"
fi

# Fallback: second bullet from second commit
if [[ -z "$BULLET2" ]]; then
  BULLET2="$(git log main..HEAD --format='%s' --reverse 2>/dev/null | sed -n '2p' || echo "")"
fi

# Detect type from title keywords
if echo "$TITLE" | grep -qiE "fix|bug|patch|hotfix"; then
  PR_TYPE="fix"
elif echo "$TITLE" | grep -qiE "chore|refactor|cleanup|maintenance|dependency|upgrade"; then
  PR_TYPE="chore"
fi

# ─── Convention checks ───
# Load org-specific conventions from profile

CONV_CHANGELOG=false
CONV_LIB_BUMP=false

# Detect org from remote URL
ORG_NAME="$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' || echo "")"

# Check if a profile has conventions for this org
for profile_file in "$HOUSTON_DIR"/profiles/*.toml; do
  [[ -f "$profile_file" ]] || continue
  # Simple TOML parsing: check for [conventions.gitlab.<org>] or [conventions.github.<org>]
  if grep -q "\[conventions\.\(gitlab\|github\)\.$ORG_NAME\]" "$profile_file" 2>/dev/null; then
    # Read convention flags (simple grep-based TOML parsing)
    section_found=false
    while IFS= read -r line; do
      if [[ "$line" == "[conventions."*"$ORG_NAME]" ]]; then
        section_found=true
        continue
      fi
      if $section_found; then
        [[ "$line" == "["* ]] && break  # next section
        case "$line" in
          changelog*=*true*)  CONV_CHANGELOG=true ;;
          lib_bump*=*true*)   CONV_LIB_BUMP=true ;;
        esac
      fi
    done < "$profile_file"
    break
  fi
done

# Check changelog exists if required
if $CONV_CHANGELOG; then
  if [[ -f "CHANGELOG.md" ]]; then
    changelog_changed="$(git diff main..HEAD --name-only 2>/dev/null | grep 'CHANGELOG.md' | wc -l | tr -d ' ')"
    if [[ "$changelog_changed" -eq 0 ]]; then
      echo "WARNING: Convention requires CHANGELOG.md entry but it was not modified" >&2
    fi
  fi
fi

# Check lib version bumps if required
if $CONV_LIB_BUMP; then
  props_changed="$(git diff main..HEAD --name-only 2>/dev/null | grep 'gradle.properties' || echo "")"
  if [[ -n "$props_changed" ]]; then
    echo "  Lib version changes detected in: $props_changed"
  fi
fi

# ─── Format ───

PR_TITLE="${PR_TYPE}(${AREA}): ${TITLE} [${TICKET_ID}]"
PR_BODY="- ${BULLET1}"
if [[ -n "$BULLET2" ]]; then
  PR_BODY="${PR_BODY}
- ${BULLET2}"
fi

# ─── Get reviewers ───
# Try context.json first (from pipeline run), fall back to detecting profile directly

REVIEWERS=""
CONTEXT_JSON=""

if [[ -f "$RUN_DIR/context.json" ]]; then
  CONTEXT_JSON="$RUN_DIR/context.json"
elif [[ -x "$HOUSTON_DIR/pipeline/detect-context.sh" ]]; then
  # No context.json — detect profile from current repo
  DETECT_OUTPUT="$("$HOUSTON_DIR/pipeline/detect-context.sh" "$(pwd)" "$HOUSTON_DIR/profiles" 2>/dev/null)" || true
  if [[ -n "$DETECT_OUTPUT" ]]; then
    CONTEXT_JSON="$(mktemp)"
    echo "$DETECT_OUTPUT" > "$CONTEXT_JSON"
    CLEANUP_CONTEXT=true
  fi
fi

if [[ -n "$CONTEXT_JSON" && -f "$CONTEXT_JSON" ]]; then
  REPO_NAME="$(basename "$(pwd)")"
  # Get org/repo from remote for matching patterns like "stitch-Money/*"
  ORG_REPO="$(echo "$REMOTE_URL" | sed 's/.*[:/]//' | sed 's/\.git$//')"

  # Match reviewers: convert glob patterns (e.g. "stitch-Money/*") to regex,
  # then test against repo name and org/repo path
  # shellcheck disable=SC2016
  get_reviewers_jq='
    def glob_to_regex: gsub("\\*"; ".*") | gsub("\\?"; ".");
    . as $r |
    ($r | to_entries | map(select(.key != "*")) | map(select(
      (.key | glob_to_regex) as $pat |
      ($repo | test($pat)) or ($org_repo | test($pat))
    )) | .[0].value // []) as $specific |
    if ($specific | length) > 0 then $specific
    else ($r["*"] // [])
    end | join(",")
  '

  if [[ "$PLATFORM" == "github" ]]; then
    REVIEWERS="$(jq -r --arg repo "$REPO_NAME" --arg org_repo "$ORG_REPO" \
      ".reviewers.github as \$r | \$r | $get_reviewers_jq" \
      "$CONTEXT_JSON" 2>/dev/null || echo "")"
  elif [[ "$PLATFORM" == "gitlab" ]]; then
    REVIEWERS="$(jq -r --arg repo "$REPO_NAME" --arg org_repo "$ORG_REPO" \
      ".reviewers.gitlab as \$r | \$r | $get_reviewers_jq" \
      "$CONTEXT_JSON" 2>/dev/null || echo "")"
  fi
fi

# Clean up temp context file if we created one
if [[ "${CLEANUP_CONTEXT:-}" == "true" && -f "$CONTEXT_JSON" ]]; then
  rm -f "$CONTEXT_JSON"
fi

# ─── Push and create ───

echo "Pushing ${BRANCH}..."
git push -u origin "$BRANCH" 2>&1 || true

echo ""
echo "Creating PR/MR..."
echo "  Title:     $PR_TITLE"
echo "  Reviewers: ${REVIEWERS:-none}"
echo "  Platform:  $PLATFORM"
echo ""

PR_URL=""

if [[ "$PLATFORM" == "github" ]]; then
  GH_ARGS=(pr create --title "$PR_TITLE" --body "$PR_BODY" --head "$BRANCH")
  if [[ -n "$REVIEWERS" ]]; then
    GH_ARGS+=(--reviewer "$REVIEWERS")
  fi

  PR_URL="$(gh "${GH_ARGS[@]}" 2>&1)" || true

  # Enable auto-merge with squash + delete branch
  if [[ "$PR_URL" == http* ]]; then
    gh pr merge "$BRANCH" --auto --squash --delete-branch 2>/dev/null || true
    echo "  Auto-merge: enabled (squash + delete branch)"
  fi

elif [[ "$PLATFORM" == "gitlab" ]]; then
  # Get current git username for assignee
  GL_USERNAME="$(glab api user 2>/dev/null | jq -r '.username // empty' 2>/dev/null || echo "")"

  GL_ARGS=(mr create
    --title "$PR_TITLE"
    --description "$PR_BODY"
    --squash-before-merge
    --remove-source-branch
    --yes)
  if [[ -n "$REVIEWERS" ]]; then
    GL_ARGS+=(--reviewer "$REVIEWERS")
  fi
  if [[ -n "$GL_USERNAME" ]]; then
    GL_ARGS+=(--assignee "$GL_USERNAME")
  fi

  PR_URL="$(glab "${GL_ARGS[@]}" 2>&1)" || true

  # Enable auto-merge after creation
  if [[ "$PR_URL" == *"merge_requests"* ]]; then
    mr_number="$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")"
    if [[ -n "$mr_number" ]]; then
      glab mr merge "$mr_number" --auto-merge --squash --remove-source-branch --yes 2>/dev/null || true
      echo "  Auto-merge: enabled (squash + delete branch)"
    fi
  fi
fi

echo ""
if [[ -n "$PR_URL" ]]; then
  echo "PR/MR created: $PR_URL"

  # Save URL to state if run dir exists
  if [[ -f "$RUN_DIR/state.json" ]]; then
    tmp=$(mktemp)
    jq --arg url "$PR_URL" '.pr_url = $url' "$RUN_DIR/state.json" > "$tmp" && mv "$tmp" "$RUN_DIR/state.json"
  fi
else
  echo "WARNING: PR/MR creation may have failed. Check output above."
fi
