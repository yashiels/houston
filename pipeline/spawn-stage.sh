#!/usr/bin/env bash
# spawn-stage.sh — Launch a disposable Claude session for a single pipeline stage.
# Reads state and context, substitutes placeholders in a template, then runs
# claude with the resulting prompt.
#
# Usage: ./pipeline/spawn-stage.sh <ticket-id> <template-name> [timeout-seconds]
#   ticket-id      — e.g., SWITCH-167
#   template-name  — filename under $HOUSTON_DIR/templates/  (e.g. researcher.md)
#   timeout-seconds — optional, default 1800 (30 min)

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
TICKET_ID="${1:-}"
TEMPLATE_NAME="${2:-}"
TIMEOUT="${3:-1800}"

if [[ -z "$TICKET_ID" || -z "$TEMPLATE_NAME" ]]; then
  echo '{"error":"Usage: spawn-stage.sh <ticket-id> <template-name> [timeout-seconds]"}' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HOUSTON_DIR="${HOUSTON_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)}"
RUN_DIR="${HOME}/.houston/runs/${TICKET_ID}"
STATE_FILE="${RUN_DIR}/state.json"
CONTEXT_FILE="${RUN_DIR}/context.json"

# Derive log name: strip extension from template name
STAGE_NAME="${TEMPLATE_NAME%.*}"
LOG_DIR="${RUN_DIR}/logs"
LOG_FILE="${LOG_DIR}/stage-${STAGE_NAME}.log"

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
if [[ ! -f "$STATE_FILE" ]]; then
  echo "{\"error\":\"state.json not found for ticket ${TICKET_ID}\",\"path\":\"${STATE_FILE}\"}" >&2
  exit 1
fi

TEMPLATE_FILE="${HOUSTON_DIR}/templates/${TEMPLATE_NAME}"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "{\"error\":\"Template not found\",\"template\":\"${TEMPLATE_NAME}\",\"path\":\"${TEMPLATE_FILE}\"}" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo '{"error":"claude command not found. Install Claude Code CLI first."}' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read state values via jq
# ---------------------------------------------------------------------------
REPO_PATH="$(jq -r '.repo_path // empty' "$STATE_FILE")"
PROFILE="$(jq -r '.profile // empty' "$STATE_FILE")"
PLATFORM="$(jq -r '.platform // empty' "$STATE_FILE")"
CLI="$(jq -r '.cli // empty' "$STATE_FILE")"
BRANCH="$(jq -r '.branch // empty' "$STATE_FILE")"

# Expand RUN_DIR to absolute path (resolve ~ if present)
ABS_RUN_DIR="$(cd "$RUN_DIR" && pwd)"

# ---------------------------------------------------------------------------
# Read and substitute template
# ---------------------------------------------------------------------------
TEMPLATE_CONTENT="$(<"$TEMPLATE_FILE")"

PROMPT="${TEMPLATE_CONTENT}"
PROMPT="${PROMPT//\{\{TICKET_ID\}\}/${TICKET_ID}}"
PROMPT="${PROMPT//\{\{RUN_DIR\}\}/${ABS_RUN_DIR}}"
PROMPT="${PROMPT//\{\{REPO_PATH\}\}/${REPO_PATH}}"
PROMPT="${PROMPT//\{\{PROFILE\}\}/${PROFILE}}"
PROMPT="${PROMPT//\{\{PLATFORM\}\}/${PLATFORM}}"
PROMPT="${PROMPT//\{\{CLI\}\}/${CLI}}"
PROMPT="${PROMPT//\{\{BRANCH\}\}/${BRANCH}}"

# ---------------------------------------------------------------------------
# Prepare log directory
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Launch Claude
# ---------------------------------------------------------------------------
CLAUDE_EXIT=0

run_claude() {
  cd "$REPO_PATH"
  claude --dangerously-skip-permissions -p "$PROMPT" 2>&1 | tee "$LOG_FILE"
  return "${PIPESTATUS[0]}"
}

if command -v timeout >/dev/null 2>&1; then
  # GNU/BSD timeout available
  cd "$REPO_PATH"
  timeout "$TIMEOUT" bash -c "$(declare -f run_claude); run_claude" || CLAUDE_EXIT=$?
  # timeout returns 124 on expiry — still propagate it
else
  run_claude || CLAUDE_EXIT=$?
fi

exit "$CLAUDE_EXIT"
