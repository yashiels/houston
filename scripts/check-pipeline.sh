#!/usr/bin/env bash
# check-pipeline.sh — Check CI/CD pipeline status for the current branch.
#
# Usage: ./scripts/check-pipeline.sh [--branch <name>] [--wait] [--max-wait <seconds>]
#
# Auto-detects platform (GitHub/GitLab) from git remote.
# If --wait, polls until all jobs complete (default max 600s).
# Outputs pipeline status as JSON to stdout; messages to stderr.

set -euo pipefail

# ─── Parse arguments ───

BRANCH=""
WAIT_MODE=false
MAX_WAIT=600
POLL_INTERVAL=30

while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)   BRANCH="$2"; shift ;;
    --wait)     WAIT_MODE=true ;;
    --max-wait) MAX_WAIT="$2"; shift ;;
    -h|--help)
      echo "Usage: ./scripts/check-pipeline.sh [--branch <name>] [--wait] [--max-wait <seconds>]" >&2
      exit 0
      ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          echo "Unknown argument: $1" >&2; exit 1 ;;
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

# ─── Helper: format duration ───

format_duration() {
  local seconds="$1"
  if [[ "$seconds" -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ "$seconds" -lt 3600 ]]; then
    echo "$(( seconds / 60 ))m$(( seconds % 60 ))s"
  else
    echo "$(( seconds / 3600 ))h$(( (seconds % 3600) / 60 ))m"
  fi
}

# ─── GitHub: fetch pipeline status ───

github_fetch_pipeline() {
  local branch="$1"
  local owner_repo
  owner_repo="$(echo "$REMOTE_URL" | sed -E 's#(https?://[^/]+/|git@[^:]+:)##' | sed 's/\.git$//')"

  echo "Fetching checks for branch '$branch' on ${owner_repo}..." >&2

  # Get the latest commit SHA for the branch
  local sha
  sha="$(git rev-parse "origin/${branch}" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "")"

  if [[ -z "$sha" ]]; then
    echo "ERROR: Cannot determine commit SHA for branch '$branch'" >&2
    return 1
  fi

  # Fetch check runs for the commit
  local check_runs
  check_runs="$(gh api "repos/${owner_repo}/commits/${sha}/check-runs" 2>/dev/null || echo '{"check_runs":[]}')"

  local jobs overall_status pipeline_url

  jobs="$(echo "$check_runs" | jq -c '
    [.check_runs[] | {
      name: .name,
      status: (
        if .status == "completed" then
          (if .conclusion == "success" then "passed"
           elif .conclusion == "failure" then "failed"
           elif .conclusion == "cancelled" then "cancelled"
           elif .conclusion == "skipped" then "skipped"
           else .conclusion
           end)
        elif .status == "in_progress" then "running"
        elif .status == "queued" then "pending"
        else .status
        end
      ),
      duration: (
        if .started_at and .completed_at then
          ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601) | tostring) + "s"
        elif .started_at then
          "running"
        else
          "-"
        end
      ),
      url: .details_url
    }]
  ' 2>/dev/null || echo '[]')"

  # Also check for status checks (some CI systems use the status API)
  local status_checks
  status_checks="$(gh api "repos/${owner_repo}/commits/${sha}/status" 2>/dev/null | jq -c '
    [.statuses[] | {
      name: .context,
      status: (
        if .state == "success" then "passed"
        elif .state == "failure" then "failed"
        elif .state == "pending" then "pending"
        elif .state == "error" then "failed"
        else .state
        end
      ),
      duration: "-",
      url: .target_url
    }]
  ' 2>/dev/null || echo '[]')"

  # Merge check runs and status checks (deduplicate by name)
  jobs="$(jq -sc '
    (.[0] + .[1]) | group_by(.name) | map(.[0])
  ' <(echo "$jobs") <(echo "$status_checks"))"

  # Determine overall status
  local has_failed has_running has_pending
  has_failed="$(echo "$jobs" | jq '[.[] | select(.status == "failed")] | length')"
  has_running="$(echo "$jobs" | jq '[.[] | select(.status == "running")] | length')"
  has_pending="$(echo "$jobs" | jq '[.[] | select(.status == "pending")] | length')"

  if [[ "$has_failed" -gt 0 ]]; then
    overall_status="failed"
  elif [[ "$has_running" -gt 0 ]]; then
    overall_status="running"
  elif [[ "$has_pending" -gt 0 ]]; then
    overall_status="pending"
  else
    overall_status="passed"
  fi

  # Get pipeline URL (PR checks page or commit checks)
  pipeline_url="https://github.com/${owner_repo}/commit/${sha}/checks"

  local failed_jobs
  failed_jobs="$(echo "$jobs" | jq -c '[.[] | select(.status == "failed") | .name]')"

  jq -n \
    --arg platform "$PLATFORM" \
    --arg branch "$branch" \
    --arg status "$overall_status" \
    --argjson jobs "$jobs" \
    --argjson failed_jobs "$failed_jobs" \
    --arg url "$pipeline_url" \
    '{
      platform: $platform,
      branch: $branch,
      status: $status,
      jobs: $jobs,
      failed_jobs: $failed_jobs,
      url: $url
    }'
}

# ─── GitLab: fetch pipeline status ───

gitlab_fetch_pipeline() {
  local branch="$1"

  echo "Fetching pipeline for branch '$branch'..." >&2

  # Get the latest pipeline for the branch
  local pipeline_json pipeline_id pipeline_status pipeline_url

  pipeline_json="$(glab api "projects/:id/pipelines?ref=${branch}&per_page=1" 2>/dev/null || echo '[]')"

  pipeline_id="$(echo "$pipeline_json" | jq -r '.[0].id // empty' 2>/dev/null || echo "")"

  if [[ -z "$pipeline_id" ]]; then
    echo "ERROR: No pipeline found for branch '$branch'" >&2
    jq -n \
      --arg platform "$PLATFORM" \
      --arg branch "$branch" \
      '{
        platform: $platform,
        branch: $branch,
        status: "not_found",
        jobs: [],
        failed_jobs: [],
        url: ""
      }'
    return
  fi

  pipeline_status="$(echo "$pipeline_json" | jq -r '.[0].status // "unknown"')"
  pipeline_url="$(echo "$pipeline_json" | jq -r '.[0].web_url // ""')"

  echo "Pipeline #${pipeline_id}: ${pipeline_status}" >&2

  # Fetch jobs for this pipeline
  local jobs_json jobs
  jobs_json="$(glab api "projects/:id/pipelines/${pipeline_id}/jobs?per_page=100" 2>/dev/null || echo '[]')"

  jobs="$(echo "$jobs_json" | jq -c '
    [.[] | {
      name: .name,
      status: (
        if .status == "success" then "passed"
        elif .status == "failed" then "failed"
        elif .status == "running" then "running"
        elif .status == "pending" then "pending"
        elif .status == "canceled" then "cancelled"
        elif .status == "skipped" then "skipped"
        elif .status == "manual" then "manual"
        else .status
        end
      ),
      duration: (
        if .duration then
          (.duration | tostring) + "s"
        else
          "-"
        end
      ),
      url: (.web_url // "")
    }]
  ')"

  # Map pipeline status
  local overall_status
  case "$pipeline_status" in
    success)  overall_status="passed" ;;
    failed)   overall_status="failed" ;;
    running)  overall_status="running" ;;
    pending)  overall_status="pending" ;;
    canceled) overall_status="cancelled" ;;
    *)        overall_status="$pipeline_status" ;;
  esac

  local failed_jobs
  failed_jobs="$(echo "$jobs" | jq -c '[.[] | select(.status == "failed") | .name]')"

  jq -n \
    --arg platform "$PLATFORM" \
    --arg branch "$branch" \
    --arg status "$overall_status" \
    --argjson jobs "$jobs" \
    --argjson failed_jobs "$failed_jobs" \
    --arg url "$pipeline_url" \
    '{
      platform: $platform,
      branch: $branch,
      status: $status,
      jobs: $jobs,
      failed_jobs: $failed_jobs,
      url: $url
    }'
}

# ─── Fetch failed job logs ───

fetch_failed_log_snippet() {
  local job_name="$1"
  local max_lines=50

  if [[ "$PLATFORM" == "github" ]]; then
    # GitHub does not easily expose job logs via gh CLI without run ID;
    # skip log capture for now, report URL instead
    echo "(See job URL for logs)" >&2
  elif [[ "$PLATFORM" == "gitlab" ]]; then
    # Try to get job ID and trace
    local branch="$2"
    local pipeline_json pipeline_id job_id

    pipeline_json="$(glab api "projects/:id/pipelines?ref=${branch}&per_page=1" 2>/dev/null || echo '[]')"
    pipeline_id="$(echo "$pipeline_json" | jq -r '.[0].id // empty' 2>/dev/null || echo "")"

    if [[ -n "$pipeline_id" ]]; then
      job_id="$(glab api "projects/:id/pipelines/${pipeline_id}/jobs?per_page=100" 2>/dev/null | \
        jq -r --arg name "$job_name" '.[] | select(.name == $name and .status == "failed") | .id' 2>/dev/null | head -1 || echo "")"

      if [[ -n "$job_id" ]]; then
        echo "--- Last ${max_lines} lines of '${job_name}' (job #${job_id}) ---" >&2
        glab api "projects/:id/jobs/${job_id}/trace" 2>/dev/null | tail -n "$max_lines" >&2 || true
        echo "--- End of log ---" >&2
      fi
    fi
  fi
}

# ─── Main: fetch pipeline ───

fetch_pipeline() {
  if [[ "$PLATFORM" == "github" ]]; then
    github_fetch_pipeline "$BRANCH"
  elif [[ "$PLATFORM" == "gitlab" ]]; then
    gitlab_fetch_pipeline "$BRANCH"
  fi
}

# ─── Wait mode ───

if [[ "$WAIT_MODE" == true ]]; then
  echo "Waiting for pipeline to complete (max ${MAX_WAIT}s, polling every ${POLL_INTERVAL}s)..." >&2

  elapsed=0
  while [[ $elapsed -lt $MAX_WAIT ]]; do
    RESULT="$(fetch_pipeline)"
    STATUS="$(echo "$RESULT" | jq -r '.status')"

    echo "[$(date +%H:%M:%S)] Status: ${STATUS} (${elapsed}s elapsed)" >&2

    if [[ "$STATUS" != "running" && "$STATUS" != "pending" ]]; then
      # Pipeline is complete — capture failed job logs if any
      FAILED_JOBS="$(echo "$RESULT" | jq -r '.failed_jobs[]' 2>/dev/null || true)"
      if [[ -n "$FAILED_JOBS" ]]; then
        echo "" >&2
        echo "Failed jobs detected. Fetching log snippets..." >&2
        while IFS= read -r job_name; do
          fetch_failed_log_snippet "$job_name" "$BRANCH"
        done <<< "$FAILED_JOBS"
      fi

      echo "$RESULT"
      exit 0
    fi

    sleep "$POLL_INTERVAL"
    elapsed=$(( elapsed + POLL_INTERVAL ))
  done

  echo "WARNING: Max wait time (${MAX_WAIT}s) exceeded. Pipeline still: ${STATUS}" >&2
  echo "$RESULT"
  exit 1
else
  # Single check (no wait)
  RESULT="$(fetch_pipeline)"
  STATUS="$(echo "$RESULT" | jq -r '.status')"

  echo "Pipeline status: ${STATUS}" >&2

  # If failed, try to get log snippets
  if [[ "$STATUS" == "failed" ]]; then
    FAILED_JOBS="$(echo "$RESULT" | jq -r '.failed_jobs[]' 2>/dev/null || true)"
    if [[ -n "$FAILED_JOBS" ]]; then
      echo "" >&2
      echo "Failed jobs detected. Fetching log snippets..." >&2
      while IFS= read -r job_name; do
        fetch_failed_log_snippet "$job_name" "$BRANCH"
      done <<< "$FAILED_JOBS"
    fi
  fi

  echo "$RESULT"
fi
