#!/usr/bin/env bash
# create-multi-repo-mr.sh — Create MRs/PRs across multiple repos in dependency order.
#
# Usage: ./scripts/create-multi-repo-mr.sh <ticket-id> --repos <path1> <path2> ... [--type feat|fix|chore] [--title <title>]
#
# For each repo:
#   1. Detects platform (GitHub/GitLab)
#   2. Verifies a feature branch is checked out
#   3. Sorts repos by dependency chain (from repo-dependencies.json)
#   4. Pushes branch and creates MR/PR via create-pr.sh
#   5. Adds dependency comments linking upstream MRs
#   6. Outputs a summary table
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_CONFIG="$HOUSTON_DIR/profiles/repo-dependencies.json"

# ─── Parse arguments ───

TICKET_ID=""
REPO_PATHS=()
PR_TYPE=""
TITLE=""
PARSING_REPOS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --repos)
      PARSING_REPOS=true
      shift
      continue
      ;;
    --type)
      PARSING_REPOS=false
      PR_TYPE="$2"
      shift 2
      continue
      ;;
    --title)
      PARSING_REPOS=false
      TITLE="$2"
      shift 2
      continue
      ;;
    -*)
      PARSING_REPOS=false
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if $PARSING_REPOS; then
        REPO_PATHS+=("$1")
      elif [[ -z "$TICKET_ID" ]]; then
        TICKET_ID="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$TICKET_ID" ]]; then
  echo "Usage: create-multi-repo-mr.sh <ticket-id> --repos <path1> <path2> ... [--type feat|fix|chore] [--title <title>]" >&2
  exit 1
fi

if [[ ${#REPO_PATHS[@]} -eq 0 ]]; then
  echo "ERROR: No repos specified. Use --repos <path1> <path2> ..." >&2
  exit 1
fi

# ─── Resolve repo paths and detect platforms ───

declare -a REPOS=()        # repo names (basename)
declare -a PATHS=()        # absolute paths
declare -a PLATFORMS=()    # github or gitlab
declare -a BRANCHES=()     # branch names
SKIPPED=()

for repo_path in "${REPO_PATHS[@]}"; do
  abs_path="$(cd "$repo_path" 2>/dev/null && pwd)" || {
    echo "WARNING: Cannot access $repo_path — skipping" >&2
    SKIPPED+=("$repo_path")
    continue
  }

  # Detect platform from remote
  remote_url="$(git -C "$abs_path" remote get-url origin 2>/dev/null || echo "")"
  platform="unknown"
  if [[ "$remote_url" == *"github"* ]]; then
    platform="github"
  elif [[ "$remote_url" == *"gitlab"* ]]; then
    platform="gitlab"
  fi

  if [[ "$platform" == "unknown" ]]; then
    echo "WARNING: Cannot detect platform for $repo_path (remote: $remote_url) — skipping" >&2
    SKIPPED+=("$repo_path")
    continue
  fi

  # Check branch
  branch="$(git -C "$abs_path" branch --show-current 2>/dev/null || echo "")"
  if [[ -z "$branch" || "$branch" =~ ^(main|master|develop)$ ]]; then
    echo "WARNING: $repo_path is on '$branch' (not a feature branch) — skipping" >&2
    SKIPPED+=("$repo_path")
    continue
  fi

  repo_name="$(basename "$abs_path")"
  REPOS+=("$repo_name")
  PATHS+=("$abs_path")
  PLATFORMS+=("$platform")
  BRANCHES+=("$branch")
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "ERROR: No valid repos to process after validation." >&2
  exit 1
fi

# ─── Sort repos by dependency order ───

# Build a mapping from repo name to its index in the dependency chain.
# Repos not found in any chain get index 9999 (treated as independent, sorted last).
# Uses parallel indexed arrays instead of associative arrays for bash 3.2 compatibility.
DEP_ORDER_KEYS=()
DEP_ORDER_VALS=()
CHAIN_DESCRIPTION=""

# Helper: look up dep order for a repo name
_dep_order_get() {
  local repo="$1"
  for _i in "${!DEP_ORDER_KEYS[@]}"; do
    if [[ "${DEP_ORDER_KEYS[$_i]}" == "$repo" ]]; then
      echo "${DEP_ORDER_VALS[$_i]}"
      return
    fi
  done
  echo ""
}

# Helper: set dep order for a repo name
_dep_order_set() {
  local repo="$1" val="$2"
  for _i in "${!DEP_ORDER_KEYS[@]}"; do
    if [[ "${DEP_ORDER_KEYS[$_i]}" == "$repo" ]]; then
      DEP_ORDER_VALS[$_i]="$val"
      return
    fi
  done
  DEP_ORDER_KEYS+=("$repo")
  DEP_ORDER_VALS+=("$val")
}

if [[ -f "$DEPS_CONFIG" ]]; then
  # Iterate over all chains and match repos by path_pattern or repo name
  chain_names="$(jq -r '.chains | keys[]' "$DEPS_CONFIG" 2>/dev/null)" || chain_names=""

  for chain_name in $chain_names; do
    chain_len="$(jq -r ".chains[\"$chain_name\"].order | length" "$DEPS_CONFIG")"
    for ((idx = 0; idx < chain_len; idx++)); do
      dep_repo="$(jq -r ".chains[\"$chain_name\"].order[$idx].repo" "$DEPS_CONFIG")"
      dep_pattern="$(jq -r ".chains[\"$chain_name\"].order[$idx].path_pattern" "$DEPS_CONFIG")"

      for ((r = 0; r < ${#REPOS[@]}; r++)); do
        matched=false
        # Match by exact repo name
        if [[ "${REPOS[$r]}" == "$dep_repo" ]]; then
          matched=true
        fi
        # Match by path pattern (convert glob ** to regex)
        if ! $matched && [[ -n "$dep_pattern" ]]; then
          regex_pattern="$(echo "$dep_pattern" | sed 's|\*\*|.*|g' | sed 's|\*|[^/]*|g')"
          if [[ "${PATHS[$r]}" =~ $regex_pattern ]]; then
            matched=true
          fi
        fi

        if $matched; then
          _dep_order_set "${REPOS[$r]}" "$idx"
          if [[ -z "$CHAIN_DESCRIPTION" ]]; then
            CHAIN_DESCRIPTION="$(jq -r ".chains[\"$chain_name\"].description // \"\"" "$DEPS_CONFIG")"
          fi
        fi
      done
    done
  done
fi

# Assign default order for unmatched repos
for ((r = 0; r < ${#REPOS[@]}; r++)); do
  existing="$(_dep_order_get "${REPOS[$r]}")"
  if [[ -z "$existing" ]]; then
    _dep_order_set "${REPOS[$r]}" 9999
  fi
done

# Build sorted index array
SORTED_INDICES=()
for ((r = 0; r < ${#REPOS[@]}; r++)); do
  SORTED_INDICES+=("$r")
done

# Bubble sort by dependency order (small list, fine for ~6 repos)
for ((i = 0; i < ${#SORTED_INDICES[@]}; i++)); do
  for ((j = i + 1; j < ${#SORTED_INDICES[@]}; j++)); do
    idx_i="${SORTED_INDICES[$i]}"
    idx_j="${SORTED_INDICES[$j]}"
    order_i="$(_dep_order_get "${REPOS[$idx_i]}")"
    order_j="$(_dep_order_get "${REPOS[$idx_j]}")"
    if [[ "$order_i" -gt "$order_j" ]]; then
      SORTED_INDICES[$i]="$idx_j"
      SORTED_INDICES[$j]="$idx_i"
    fi
  done
done

# ─── Create MRs in dependency order ───

echo ""
echo "Multi-Repo MR Creation — $TICKET_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

declare -a MR_URLS=()
declare -a MR_REPOS=()
declare -a MR_PLATFORMS=()
PREV_MR_URL=""
PREV_REPO=""

for sorted_idx in "${SORTED_INDICES[@]}"; do
  repo="${REPOS[$sorted_idx]}"
  abs_path="${PATHS[$sorted_idx]}"
  platform="${PLATFORMS[$sorted_idx]}"
  branch="${BRANCHES[$sorted_idx]}"

  echo "[$((${#MR_URLS[@]} + 1))/${#SORTED_INDICES[@]}] $repo ($platform)"
  echo "  Branch: $branch"

  # Build create-pr.sh arguments
  PR_ARGS=("$TICKET_ID")
  if [[ -n "$PR_TYPE" ]]; then
    PR_ARGS+=(--type "$PR_TYPE")
  fi
  if [[ -n "$TITLE" ]]; then
    PR_ARGS+=(--title "$TITLE")
  fi

  # Check for Houston run directory
  RUN_DIR="$HOME/.houston/runs/$TICKET_ID"
  if [[ -d "$RUN_DIR" ]]; then
    PR_ARGS+=(--run-dir "$RUN_DIR")
  fi

  # Run create-pr.sh from within the repo directory
  mr_output=""
  mr_url=""
  if mr_output="$(cd "$abs_path" && "$SCRIPT_DIR/create-pr.sh" "${PR_ARGS[@]}" 2>&1)"; then
    # Extract URL from output — look for http(s) URL on a line containing "created"
    mr_url="$(echo "$mr_output" | grep -oE 'https?://[^ ]+' | tail -1 || echo "")"
  fi

  if [[ -z "$mr_url" ]]; then
    # Try to extract any URL from the output as fallback
    mr_url="$(echo "$mr_output" | grep -oE 'https?://[^ ]+' | head -1 || echo "")"
  fi

  if [[ -n "$mr_url" ]]; then
    echo "  MR/PR: $mr_url"
    MR_URLS+=("$mr_url")
  else
    echo "  WARNING: Could not extract MR/PR URL from output" >&2
    echo "  Output: $mr_output" >&2
    MR_URLS+=("(failed)")
  fi
  MR_REPOS+=("$repo")
  MR_PLATFORMS+=("$platform")

  # Add MR dependency (blocking merge request) if there is an upstream MR
  if [[ -n "$PREV_MR_URL" && "$PREV_MR_URL" != "(failed)" && "$mr_url" != "" ]]; then
    if [[ "$platform" == "gitlab" ]]; then
      mr_number="$(echo "$mr_url" | grep -oE '[0-9]+$' || echo "")"
      # Extract project path and MR iid from upstream URL for cross-project ref
      # URL format: https://gitlab.com/<group>/<subgroup>/<project>/-/merge_requests/<iid>
      prev_mr_ref="$(echo "$PREV_MR_URL" | sed -E 's|https?://[^/]+/||; s|/-/merge_requests/|!|')"
      if [[ -n "$mr_number" && -n "$prev_mr_ref" ]]; then
        # Use GitLab API to set blocking MR dependency
        # The API requires at least one standard field alongside blocking refs
        project_id="$(cd "$abs_path" && glab api "projects/:id" 2>/dev/null | jq -r '.id' 2>/dev/null || echo "")"
        current_title="$(cd "$abs_path" && glab api "projects/$project_id/merge_requests/$mr_number" 2>/dev/null | jq -r '.title' 2>/dev/null || echo "")"
        if [[ -n "$project_id" && -n "$current_title" ]]; then
          (cd "$abs_path" && glab api --method PUT "projects/$project_id/merge_requests/$mr_number" \
            -f "title=$current_title" \
            -f "blocking_merge_requests_references[]=$prev_mr_ref" 2>/dev/null) > /dev/null 2>&1 || \
            echo "  WARNING: Could not set MR dependency via API" >&2
          echo "  MR dependency set -> $PREV_REPO ($prev_mr_ref)"
        fi
        # Also add a comment for visibility
        dep_comment="Depends on: $PREV_MR_URL ($PREV_REPO must be merged first)"
        (cd "$abs_path" && glab mr note "$mr_number" --message "$dep_comment" 2>/dev/null) || true
      fi
    elif [[ "$platform" == "github" ]]; then
      pr_number="$(echo "$mr_url" | grep -oE '[0-9]+$' || echo "")"
      if [[ -n "$pr_number" ]]; then
        dep_comment="Depends on: $PREV_MR_URL ($PREV_REPO must be merged first)"
        (cd "$abs_path" && gh pr comment "$pr_number" --body "$dep_comment" 2>/dev/null) || \
          echo "  WARNING: Could not add dependency comment to GitHub PR" >&2
      fi
    fi
  fi

  # Track previous MR for dependency linking
  if [[ -n "$mr_url" && "$mr_url" != "(failed)" ]]; then
    PREV_MR_URL="$mr_url"
    PREV_REPO="$repo"
  fi

  echo ""
done

# ─── Output summary ───

echo ""
echo "Multi-Repo MR Summary — $TICKET_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Print table header
printf "%-6s %-24s %-10s %s\n" "Order" "Repo" "Platform" "MR/PR"

for ((i = 0; i < ${#MR_REPOS[@]}; i++)); do
  printf "%-6s %-24s %-10s %s\n" "$((i + 1))" "${MR_REPOS[$i]}" "${MR_PLATFORMS[$i]}" "${MR_URLS[$i]}"
done

# Build and print dependency chain (only repos in a known chain, in order)
CHAIN_PARTS=()
for ((i = 0; i < ${#MR_REPOS[@]}; i++)); do
  order="$(_dep_order_get "${MR_REPOS[$i]}")"
  order="${order:-9999}"
  if [[ "$order" -lt 9999 ]]; then
    CHAIN_PARTS+=("${MR_REPOS[$i]}")
  fi
done

if [[ ${#CHAIN_PARTS[@]} -gt 1 ]]; then
  echo ""
  echo "Dependency Chain:"
  chain_str="  ${CHAIN_PARTS[0]}"
  for ((i = 1; i < ${#CHAIN_PARTS[@]}; i++)); do
    chain_str="$chain_str -> ${CHAIN_PARTS[$i]}"
  done
  echo "$chain_str"
fi

# Print skipped repos
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped:"
  for s in "${SKIPPED[@]}"; do
    echo "  - $s"
  done
fi

echo ""
echo "Note: Merge in order. Each downstream MR depends on its upstream being merged first."
