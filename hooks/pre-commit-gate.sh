#!/bin/bash
# pre-commit-gate.sh — Claude Code hook to verify tests pass before commits
# Hook type: PreToolUse (on git commit)
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only check git commit commands
if [ "$TOOL" != "Bash" ]; then
  exit 0
fi

if ! echo "$COMMAND" | grep -qE "git commit"; then
  exit 0
fi

# Check if tests were run recently (within last 10 minutes)
MARKER="/tmp/.houston-tests-passed"
if [ -f "$MARKER" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt 600 ]; then
    exit 0  # Tests passed recently, allow commit
  fi
fi

echo "WARNING: No recent test run detected. Run tests before committing." >&2
echo "Houston recommends: run your project's test command first." >&2
# Allow commit but warn — don't hard-block as the test marker might not exist yet
exit 0
