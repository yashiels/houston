#!/usr/bin/env bash
# pre-commit-gate.sh — Block git commit if tests haven't passed
# Called by .claude/settings.json PreToolUse hook (on git commit).
#
# Checks for a recent test pass marker file. If tests haven't been run
# or failed, blocks the commit.
#
# Exit codes:
#   0 — allow the commit
#   2 — block with message on stdout

set -euo pipefail

TOOL="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Only check Bash tool calls that contain "git commit"
if [[ "$TOOL" != "Bash" ]]; then
  exit 0
fi

CMD=""
if [ -n "$TOOL_INPUT" ]; then
  CMD=$(echo "$TOOL_INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")
fi

# Only gate actual git commit commands
if ! echo "$CMD" | grep -qE 'git\s+commit'; then
  exit 0
fi

# Check for test pass marker (created by post-edit-tests or manual test runs)
MARKER="$PROJECT_DIR/.autonomous-dev/.tests-passed"

if [ -f "$MARKER" ]; then
  # Check marker age (must be less than 10 minutes old)
  MARKER_AGE=$(($(date +%s) - $(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0)))
  if [ "$MARKER_AGE" -lt 600 ]; then
    # Tests passed recently, allow commit
    exit 0
  fi
fi

# No recent test pass — block and provide guidance
echo "BLOCK: Cannot commit — tests have not been verified recently."
echo ""
echo "Run tests first, then commit:"
echo "  1. Run the project's test command (e.g., npm test, pnpm test, pytest)"
echo "  2. Run typecheck if applicable"
echo "  3. Then retry the commit"
echo ""
echo "Or run the quality gate:"
echo "  ./scripts/quality-gate.sh --scope story"
echo ""
echo "To create the test pass marker manually after verification:"
echo "  mkdir -p .autonomous-dev && touch .autonomous-dev/.tests-passed"
exit 2
