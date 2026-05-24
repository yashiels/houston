#!/usr/bin/env bash
# pipeline-guard.sh — Block Edit/Write without an active pipeline.
# Called by .claude/settings.json PreToolUse hook.
#
# Environment (set by Claude Code):
#   CLAUDE_TOOL_NAME   — the tool being invoked (Edit, Write, Bash, etc.)
#   CLAUDE_TOOL_INPUT  — JSON string with tool parameters
#   CLAUDE_PROJECT_DIR — the project root directory
#
# Exit codes:
#   0 — allow the tool call
#   2 — block with message on stdout

set -euo pipefail

TOOL="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.autonomous-dev/state.json"

# Only guard Edit and Write tools
if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
  exit 0
fi

# Extract file_path from tool input JSON
FILE_PATH=""
if [ -n "$TOOL_INPUT" ]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('file_path', data.get('filePath', '')))
except:
    print('')
" 2>/dev/null || echo "")
fi

# Allow pipeline infrastructure edits (always OK)
if [[ "$FILE_PATH" == *".autonomous-dev/"* ]] || \
   [[ "$FILE_PATH" == *".claude/"* ]] || \
   [[ "$FILE_PATH" == *"autonomous-dev/"* ]]; then
  exit 0
fi

# Allow root-level markdown files (CLAUDE.md, AGENTS.md, etc.)
BASENAME="$(basename "$FILE_PATH")"
DIRNAME="$(dirname "$FILE_PATH")"
if [[ "$BASENAME" == *.md ]] && [[ "$DIRNAME" == "$PROJECT_DIR" || "$DIRNAME" == "." ]]; then
  exit 0
fi

# Allow config files (package.json, tsconfig, etc.)
case "$BASENAME" in
  *.json|*.yaml|*.yml|*.toml|*.config.*|*.rc|*.env*)
    exit 0
    ;;
esac

# Check pipeline state exists
if [ ! -f "$STATE_FILE" ]; then
  echo "BLOCK: No pipeline active. Start the autonomous dev pipeline first."
  echo "  Run: ./scripts/orchestrate.sh \"<description-or-linear-url>\""
  echo "  Or:  ac init \"<description-or-linear-url>\""
  exit 2
fi

# Read current phase
PHASE=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
print(state.get('phase', 'unknown'))
" 2>/dev/null || echo "unknown")

# Block during research and planning phases
case "$PHASE" in
  init|research|plan)
    echo "BLOCK: Cannot edit source files during '$PHASE' phase."
    echo "  The pipeline must reach 'implement' phase before code changes are allowed."
    echo "  Current phase: $PHASE"
    exit 2
    ;;
esac

# Allow during implement, review, simplify, complete, preflight
exit 0
