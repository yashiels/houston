#!/bin/bash
# spawn-coder.sh — Spawn Claude Code for a story
# Usage: ./scripts/spawn-coder.sh <STORY_ID> <PROJECT_PATH> [MODEL]
#
# Tashmia calls this instead of trying to construct the claude CLI command herself.
# The script handles all the complexity: model selection, prompt construction,
# co-author enforcement, and background execution.

set -u

STORY_ID="${1:?Usage: spawn-coder.sh <STORY_ID> <PROJECT_PATH> [MODEL]}"
PROJECT_PATH="${2:?Usage: spawn-coder.sh <STORY_ID> <PROJECT_PATH> [MODEL]}"
EXPLICIT_MODEL="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(dirname "$SCRIPT_DIR")"

# Source config for co-author
if [ -f "$PIPELINE_DIR/config.sh" ]; then
  # shellcheck source=/dev/null
  source "$PIPELINE_DIR/config.sh"
fi
CO_AUTHOR="${AD_CO_AUTHOR:-Yashiel Sookdeo <yashiel@skyner.co.za>}"

# Resolve model from preset if not explicitly provided
MODEL="claude-sonnet-4-6"
if [ -n "$EXPLICIT_MODEL" ]; then
  MODEL="$EXPLICIT_MODEL"
elif [ -f "$PROJECT_PATH/.autonomous-dev/state.json" ]; then
  ALIAS=$(jq -r '.models.coder // "sonnet"' "$PROJECT_PATH/.autonomous-dev/state.json" 2>/dev/null)
  case "$ALIAS" in
    opus)   MODEL="claude-opus-4-6" ;;
    sonnet) MODEL="claude-sonnet-4-6" ;;
    haiku)  MODEL="claude-haiku-4-5-20251001" ;;
    *)      MODEL="claude-sonnet-4-6" ;;
  esac
fi
echo "Model: $MODEL (from ${EXPLICIT_MODEL:-preset})"

# Read story from prd.json
STORY_JSON=""
if [ -f "$PROJECT_PATH/prd.json" ]; then
  STORY_JSON=$(jq -r ".userStories[] | select(.id==\"$STORY_ID\")" "$PROJECT_PATH/prd.json" 2>/dev/null)
fi

if [ -z "$STORY_JSON" ]; then
  echo "{\"error\":\"Story $STORY_ID not found in prd.json\"}"
  exit 1
fi

STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title // "unknown"')
BRANCH=$(cd "$PROJECT_PATH" && git branch --show-current 2>/dev/null || echo "unknown")

PROMPT="Implement $STORY_ID: $STORY_TITLE

Project: $PROJECT_PATH
Branch: $BRANCH

Story details:
$(echo "$STORY_JSON" | jq -r '.')

Instructions:
1. Read the story acceptance criteria above
2. Implement the feature with tests
3. Run: flutter test (or the appropriate test command)
4. If tests pass, commit with message: '$STORY_ID: $STORY_TITLE'
5. Include trailer: Co-Authored-By: $CO_AUTHOR
6. NEVER add any AI/Claude co-author lines
7. Output STORY_COMPLETE when done, or STORY_BLOCKED with reason if stuck"

# Spawn Claude Code and capture result
cd "$PROJECT_PATH" || exit 1
OUTPUT=$(claude --model "$MODEL" --permission-mode bypassPermissions --print "$PROMPT" 2>&1)
EXIT_CODE=$?

# Extract result
if echo "$OUTPUT" | grep -q "STORY_COMPLETE"; then
  STATUS="complete"
  LAST_COMMIT=$(git log --oneline -1 2>/dev/null)
  SUMMARY="$STORY_ID done. Commit: $LAST_COMMIT"
elif echo "$OUTPUT" | grep -q "STORY_BLOCKED"; then
  STATUS="blocked"
  REASON=$(echo "$OUTPUT" | grep "STORY_BLOCKED" | head -1)
  SUMMARY="$STORY_ID blocked: $REASON"
else
  STATUS="unknown"
  SUMMARY="$STORY_ID finished with exit code $EXIT_CODE"
fi

# Notify OpenClaw so Tashmia wakes up and reports to Discord
openclaw system event --text "$SUMMARY" --mode now 2>/dev/null || true

# Output for process log
echo ""
echo "=== SPAWN-CODER RESULT ==="
echo "story: $STORY_ID"
echo "status: $STATUS"
echo "summary: $SUMMARY"
echo "exit_code: $EXIT_CODE"
