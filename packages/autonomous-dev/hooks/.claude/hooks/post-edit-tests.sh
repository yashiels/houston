#!/usr/bin/env bash
# post-edit-tests.sh — Run relevant tests after file edits
# Called by .claude/settings.json PostToolUse hook.
#
# After an Edit or Write tool modifies a source file, this hook runs
# the relevant tests to catch regressions immediately.
#
# Environment (set by Claude Code):
#   CLAUDE_TOOL_NAME  — the tool that was invoked
#   CLAUDE_TOOL_INPUT — JSON string with tool parameters

set -euo pipefail

TOOL="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Only trigger on Edit and Write tools
if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
  exit 0
fi

# Extract file_path from tool input
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

[ -z "$FILE_PATH" ] && exit 0

# Skip non-source files (docs, configs, etc.)
case "$FILE_PATH" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.txt|*.env*|*.gitignore)
    exit 0
    ;;
esac

# Skip test files themselves (avoid infinite loops)
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__/*|*__mocks__/*)
    exit 0
    ;;
esac

# Skip pipeline infrastructure files
case "$FILE_PATH" in
  *.autonomous-dev/*|*.claude/*|*.pipeline/*)
    exit 0
    ;;
esac

# Detect project type and find test command
cd "$PROJECT_DIR"

TEST_CMD=""
if [ -f "package.json" ]; then
  # Node.js — try to find related test file
  BASE_NAME=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
  DIR_NAME=$(dirname "$FILE_PATH")

  # Look for corresponding test file
  TEST_FILE=""
  for pattern in "$DIR_NAME/$BASE_NAME.test.ts" "$DIR_NAME/$BASE_NAME.test.tsx" "$DIR_NAME/$BASE_NAME.test.js" "$DIR_NAME/$BASE_NAME.spec.ts" "$DIR_NAME/$BASE_NAME.spec.tsx" "$DIR_NAME/__tests__/$BASE_NAME.test.ts" "$DIR_NAME/__tests__/$BASE_NAME.test.tsx"; do
    if [ -f "$pattern" ]; then
      TEST_FILE="$pattern"
      break
    fi
  done

  if [ -n "$TEST_FILE" ]; then
    # Run specific test file
    if [ -f "pnpm-lock.yaml" ]; then
      TEST_CMD="pnpm exec vitest run $TEST_FILE 2>&1 || pnpm exec jest --no-coverage $TEST_FILE 2>&1"
    elif [ -f "yarn.lock" ]; then
      TEST_CMD="yarn vitest run $TEST_FILE 2>&1 || yarn jest --no-coverage $TEST_FILE 2>&1"
    else
      TEST_CMD="npx vitest run $TEST_FILE 2>&1 || npx jest --no-coverage $TEST_FILE 2>&1"
    fi
  fi
elif [ -f "go.mod" ]; then
  # Go — test the package containing the file
  PKG_DIR=$(dirname "$FILE_PATH")
  TEST_CMD="go test ./$PKG_DIR/... 2>&1"
elif [ -f "Cargo.toml" ]; then
  TEST_CMD="cargo test 2>&1"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  BASE_NAME=$(basename "$FILE_PATH" .py)
  DIR_NAME=$(dirname "$FILE_PATH")
  TEST_FILE=""
  for pattern in "$DIR_NAME/test_$BASE_NAME.py" "$DIR_NAME/${BASE_NAME}_test.py" "tests/test_$BASE_NAME.py"; do
    if [ -f "$pattern" ]; then
      TEST_FILE="$pattern"
      break
    fi
  done
  if [ -n "$TEST_FILE" ]; then
    TEST_CMD="pytest $TEST_FILE -x 2>&1"
  fi
fi

# Run tests if we found a command
if [ -n "$TEST_CMD" ]; then
  echo "Running tests for edited file: $(basename "$FILE_PATH")"
  if eval "$TEST_CMD" > /dev/null 2>&1; then
    # Create test pass marker
    mkdir -p "$PROJECT_DIR/.autonomous-dev"
    touch "$PROJECT_DIR/.autonomous-dev/.tests-passed"
    echo "Tests passed."
  else
    echo "WARNING: Tests may have failed after editing $(basename "$FILE_PATH"). Run full test suite to verify."
  fi
fi

exit 0
