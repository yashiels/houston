#!/usr/bin/env bash
# dispatch.sh — Launch a single ticket pipeline via agent-deck.
#
# Usage: ./scripts/dispatch.sh <ticket-id> <repo-path> [mode] [--profile name]
#   ticket-id  — e.g., SWITCH-167 (required)
#   repo-path  — path to the git repository (required)
#   mode       — supervised (default), autonomous, or human-assisted
#   --profile  — override auto-detected profile name

set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $0 <ticket-id> <repo-path> [mode] [--profile name]" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TICKET_ID=""
REPO_PATH=""
MODE="supervised"
PROFILE_OVERRIDE=""

positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE_OVERRIDE="${2:?--profile requires a name}"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

TICKET_ID="${positional[0]:-}"
REPO_PATH="${positional[1]:-}"
MODE="${positional[2]:-supervised}"

if [[ -z "$TICKET_ID" || -z "$REPO_PATH" ]]; then
  usage
fi

# Resolve repo path to absolute
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# ---------------------------------------------------------------------------
# Validate mode
# ---------------------------------------------------------------------------
case "$MODE" in
  supervised|autonomous|human-assisted) ;;
  *)
    echo "Error: invalid mode '$MODE'. Must be: supervised, autonomous, human-assisted" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Check agent-deck is installed
# ---------------------------------------------------------------------------
if ! command -v agent-deck &>/dev/null; then
  echo "Error: agent-deck is not installed or not in PATH." >&2
  echo "Install it from: https://github.com/anthropics/agent-deck" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Detect context (profile)
# ---------------------------------------------------------------------------
if ! CONTEXT_JSON="$("${HOUSTON_DIR}/pipeline/detect-context.sh" "$REPO_PATH" 2>&1)"; then
  echo "Error: profile detection failed." >&2
  echo "$CONTEXT_JSON" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Extract identity and credential info
# ---------------------------------------------------------------------------
PROFILE="$(echo "$CONTEXT_JSON" | jq -r '.profile.name')"
GIT_NAME="$(echo "$CONTEXT_JSON" | jq -r '.identity.name')"
GIT_EMAIL="$(echo "$CONTEXT_JSON" | jq -r '.identity.email')"
LINEAR_KEY_ENV="$(echo "$CONTEXT_JSON" | jq -r '.linear.api_key_env // empty')"

# Apply profile override if specified
if [[ -n "$PROFILE_OVERRIDE" ]]; then
  PROFILE="$PROFILE_OVERRIDE"
fi

# ---------------------------------------------------------------------------
# Step 3: Resolve Linear API key
# ---------------------------------------------------------------------------
if [[ -n "$LINEAR_KEY_ENV" ]]; then
  LINEAR_KEY_VALUE="${!LINEAR_KEY_ENV:-}"
  if [[ -z "$LINEAR_KEY_VALUE" ]]; then
    echo "Warning: Linear API key env var '$LINEAR_KEY_ENV' is not set. Continuing without it." >&2
  fi
else
  LINEAR_KEY_VALUE=""
  echo "Warning: No Linear API key env var configured in profile. Continuing without it." >&2
fi

# ---------------------------------------------------------------------------
# Step 4: Build branch name
# ---------------------------------------------------------------------------
TICKET_LOWER="$(echo "$TICKET_ID" | tr '[:upper:]' '[:lower:]')"
BRANCH="feat/${TICKET_LOWER}"

# ---------------------------------------------------------------------------
# Step 5: Initialize pipeline run state
# ---------------------------------------------------------------------------
if ! "${HOUSTON_DIR}/pipeline/init-pipeline.sh" "$TICKET_ID" "$REPO_PATH" "$MODE" >/dev/null; then
  echo "Error: failed to initialize pipeline run for $TICKET_ID" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 6: Launch via agent-deck with credential isolation
# ---------------------------------------------------------------------------
LAUNCH_ENV=(
  env -i
  HOME="$HOME"
  PATH="$PATH"
  HOUSTON_DIR="$HOUSTON_DIR"
  GIT_AUTHOR_NAME="$GIT_NAME"
  GIT_AUTHOR_EMAIL="$GIT_EMAIL"
  GIT_COMMITTER_NAME="$GIT_NAME"
  GIT_COMMITTER_EMAIL="$GIT_EMAIL"
)

# Only pass Linear key if it is set
if [[ -n "$LINEAR_KEY_ENV" && -n "$LINEAR_KEY_VALUE" ]]; then
  LAUNCH_ENV+=("${LINEAR_KEY_ENV}=${LINEAR_KEY_VALUE}")
fi

"${LAUNCH_ENV[@]}" \
  agent-deck launch "$REPO_PATH" \
    -c "claude --dangerously-skip-permissions" \
    -w "$BRANCH" \
    -t "$TICKET_LOWER" \
    -m "Execute Houston pipeline. Ticket: $TICKET_ID. Run: $HOUSTON_DIR/pipeline/orchestrate.sh next $TICKET_ID" \
    --no-wait -q

# ---------------------------------------------------------------------------
# Step 7: Output summary
# ---------------------------------------------------------------------------
cat <<EOF

Houston Pipeline Dispatched
  Ticket:   $TICKET_ID
  Profile:  $PROFILE
  Repo:     $REPO_PATH
  Branch:   $BRANCH
  Mode:     $MODE
  Session:  $TICKET_LOWER
  Monitor:  agent-deck
EOF
