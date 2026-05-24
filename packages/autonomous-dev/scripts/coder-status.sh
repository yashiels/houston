#!/bin/bash
# coder-status.sh — Check status of running Claude Code coder sessions
# Usage: ./scripts/coder-status.sh [PROJECT_PATH]
#
# Tashmia calls this to check if a coder is still running and what it's done.

PROJECT_PATH="${1:-$(pwd)}"

echo "=== CODER STATUS ==="

# Check for running claude processes working on this project
PIDS=$(ps aux | grep "claude.*$PROJECT_PATH\|claude.*permission-mode" | grep -v grep | awk '{print $2}')

if [ -z "$PIDS" ]; then
  echo "status: idle"
  echo "running: none"
else
  echo "status: running"
  for pid in $PIDS; do
    ELAPSED=$(ps -p "$pid" -o etime= 2>/dev/null | xargs)
    echo "pid: $pid (elapsed: $ELAPSED)"
  done
fi

# Check recent git activity
echo ""
echo "=== RECENT COMMITS ==="
cd "$PROJECT_PATH" 2>/dev/null && git log --oneline -5 2>/dev/null || echo "no git repo"

echo ""
echo "=== UNCOMMITTED CHANGES ==="
cd "$PROJECT_PATH" 2>/dev/null && git status --short 2>/dev/null | head -10 || echo "none"

echo ""
echo "=== TEST STATUS ==="
cd "$PROJECT_PATH" 2>/dev/null || true
if [ -f "pubspec.yaml" ]; then
  TEST_COUNT=$(find test -name "*_test.dart" 2>/dev/null | wc -l | xargs)
  echo "test_files: $TEST_COUNT"
fi
