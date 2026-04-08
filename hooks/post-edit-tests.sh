#!/bin/bash
# post-edit-tests.sh — Claude Code hook to run tests after file edits
# Hook type: PostToolUse (on Edit/Write)
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only trigger on Edit or Write
if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip non-source files
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.toml|*.yaml|*.yml|*.lock|*.gitignore)
    exit 0
    ;;
esac

# Mark that an edit happened — the agent should run tests
echo "Houston: Source file edited ($FILE_PATH). Remember to run tests before committing." >&2
exit 0
