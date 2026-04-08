#!/usr/bin/env bash
# init-pipeline.sh — Initialize a Houston pipeline run for a ticket.
# Creates the run directory structure, detects context and project info,
# builds state.json, and saves all outputs.
#
# Usage: ./pipeline/init-pipeline.sh <ticket-id> <repo-path> [mode] [profiles-dir]
#   ticket-id    — e.g., SWITCH-167 (required)
#   repo-path    — path to the git repo (required)
#   mode         — supervised (default), autonomous, or human-assisted
#   profiles-dir — defaults to ../profiles relative to script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Arguments ---
TICKET_ID="${1:?Usage: init-pipeline.sh <ticket-id> <repo-path> [mode] [profiles-dir]}"
REPO_PATH="${2:?Usage: init-pipeline.sh <ticket-id> <repo-path> [mode] [profiles-dir]}"
MODE="${3:-supervised}"
PROFILES_DIR="${4:-${SCRIPT_DIR}/../profiles}"

# --- Validate mode ---
case "$MODE" in
  supervised|autonomous|human-assisted)
    ;;
  *)
    echo "Error: invalid mode '${MODE}'. Must be one of: supervised, autonomous, human-assisted" >&2
    exit 1
    ;;
esac

# --- Resolve absolute paths ---
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
PROFILES_DIR="$(cd "$PROFILES_DIR" && pwd)"

# --- Create run directory ---
RUN_DIR="${HOME}/.houston/runs/${TICKET_ID}"
mkdir -p "${RUN_DIR}/research" "${RUN_DIR}/memory" "${RUN_DIR}/logs"

# --- Detect context (profile + platform) ---
CONTEXT_JSON="$("${SCRIPT_DIR}/detect-context.sh" "$REPO_PATH" "$PROFILES_DIR")"

# --- Detect project (tech stack) ---
PROJECT_JSON="$("${SCRIPT_DIR}/detect-project.sh" "$REPO_PATH")"

# --- Extract fields from context JSON ---
PROFILE="$(echo "$CONTEXT_JSON" | jq -r '.profile.name')"
PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.detected.platform')"
CLI="$(echo "$CONTEXT_JSON" | jq -r '.detected.cli')"

# --- Timestamps ---
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# --- Build state.json ---
STATE_JSON="$(jq -n \
  --argjson version 1 \
  --arg ticket_id "$TICKET_ID" \
  --arg profile "$PROFILE" \
  --arg repo_path "$REPO_PATH" \
  --arg branch "" \
  --arg mode "$MODE" \
  --arg platform "$PLATFORM" \
  --arg cli "$CLI" \
  --arg current_step "init" \
  --argjson steps_completed '[]' \
  --arg created_at "$NOW" \
  --arg updated_at "$NOW" \
  '{
    version: $version,
    ticket_id: $ticket_id,
    profile: $profile,
    repo_path: $repo_path,
    branch: $branch,
    mode: $mode,
    platform: $platform,
    cli: $cli,
    current_step: $current_step,
    steps_completed: $steps_completed,
    created_at: $created_at,
    updated_at: $updated_at
  }'
)"

# --- Save outputs ---
echo "$STATE_JSON"   > "${RUN_DIR}/state.json"
echo "$CONTEXT_JSON" > "${RUN_DIR}/context.json"
echo "$PROJECT_JSON" > "${RUN_DIR}/project.json"

# --- Output state.json to stdout ---
echo "$STATE_JSON"
