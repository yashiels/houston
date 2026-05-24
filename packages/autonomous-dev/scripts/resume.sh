#!/bin/bash
# resume.sh — Read state.json and output resume instructions
# Usage: ./scripts/resume.sh [path/to/state.json]
# Exit 0 = resume state found and valid
# Exit 1 = no state.json or invalid

set -uo pipefail

STATE_FILE="${1:-.autonomous-dev/state.json}"

if [ ! -f "$STATE_FILE" ]; then
  echo "No state.json found at $STATE_FILE — starting fresh"
  exit 1
fi

if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "ERROR: Invalid JSON in $STATE_FILE"
  exit 1
fi

# Extract key fields
VERSION=$(jq -r '.version // 1' "$STATE_FILE")
SESSION_ID=$(jq -r '.sessionId // "unknown"' "$STATE_FILE")
MODE=$(jq -r '.mode // "unknown"' "$STATE_FILE")
PRESET=$(jq -r '.preset // "unknown"' "$STATE_FILE")
STARTED_AT=$(jq -r '.startedAt // "unknown"' "$STATE_FILE")
LAST_CHECKPOINT=$(jq -r '.lastCheckpoint // "unknown"' "$STATE_FILE")
CURRENT_PHASE=$(jq -r '.currentPhase // "none"' "$STATE_FILE")
CURRENT_STORY=$(jq -r '.currentStory // "none"' "$STATE_FILE")
PROJECT_PATH=$(jq -r '.project.path // "."' "$STATE_FILE")
BRANCH=$(jq -r '.project.branch // "unknown"' "$STATE_FILE")

# Count completed and total stories
COMPLETE_STORIES=$(jq '[.stories // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE")
TOTAL_STORIES=$(jq '[.stories // {} | keys[]] | length' "$STATE_FILE")

# Count complete phases
COMPLETE_PHASES=$(jq '[.phases // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE")
TOTAL_PHASES=$(jq '[.phases // {} | keys[]] | length' "$STATE_FILE")

# List failed stories
FAILED_STORIES=$(jq -r '.stories // {} | to_entries[] | select(.value.status != "complete" and (.value.attempts // 0) > 0) | "\(.key) (attempts: \(.value.attempts), model: \(.value.model // "unknown"))"' "$STATE_FILE" 2>/dev/null || echo "none")

echo "=== RESUME STATE ==="
echo "Schema version: $VERSION"
echo "Session: $SESSION_ID"
echo "Mode: $MODE"
echo "Preset: $PRESET"
echo "Started: $STARTED_AT"
echo "Last checkpoint: $LAST_CHECKPOINT"
echo ""
echo "Project: $PROJECT_PATH"
echo "Branch: $BRANCH"
echo ""

# v2: print model config
if [ "$VERSION" = "2" ]; then
  echo "Model configuration:"
  jq -r '.models // {} | to_entries[] | "  \(.key): \(.value)"' "$STATE_FILE" 2>/dev/null || true
  echo ""
fi

echo "Progress:"
echo "  Phases: $COMPLETE_PHASES/$TOTAL_PHASES complete"
echo "  Stories: $COMPLETE_STORIES/$TOTAL_STORIES complete"
echo ""
echo "Resume from:"
echo "  Phase: $CURRENT_PHASE"
echo "  Story: $CURRENT_STORY"

if [ "$FAILED_STORIES" != "none" ] && [ -n "$FAILED_STORIES" ]; then
  echo ""
  echo "Previously failed stories (may need attention):"
  echo "$FAILED_STORIES" | while read -r line; do
    echo "  - $line"
  done
fi

echo ""
echo "Completed phases:"
jq -r '.phases // {} | to_entries[] | select(.value.status == "complete") | "  - \(.key): reviewed at \(.value.reviewedAt // "unknown")"' "$STATE_FILE" 2>/dev/null || echo "  none"

# v2: print per-story model summary for completed stories
if [ "$VERSION" = "2" ]; then
  COMPLETED_WITH_MODEL=$(jq -r '.stories // {} | to_entries[] | select(.value.status == "complete" and .value.model != null) | "  \(.key): \(.value.model)"' "$STATE_FILE" 2>/dev/null || echo "")
  if [ -n "$COMPLETED_WITH_MODEL" ]; then
    echo ""
    echo "Completed story models:"
    echo "$COMPLETED_WITH_MODEL"
  fi
fi

echo ""
echo "=== INSTRUCTIONS ==="
echo "Skip completed stories: those with status 'complete' in state.json"
echo "Skip completed phases: those with status 'complete' in state.json"
echo "Resume: start execution at phase '$CURRENT_PHASE', story '$CURRENT_STORY'"
echo "Retry limit: story '$CURRENT_STORY' has $(jq -r ".stories[\"$CURRENT_STORY\"].attempts // 0" "$STATE_FILE") previous attempt(s)"

if [ "$VERSION" = "2" ]; then
  echo ""
  echo "Model config: read state.json .models and use for all spawning"
fi

exit 0
