#!/bin/bash
# wiring-check.sh — Verify wiring checklist items
#
# Reads wiring-checklist.json and verifies each item exists in the target file.
#
# Usage: ./scripts/wiring-check.sh [path/to/wiring-checklist.json] [project-path]
# Default: ./wiring-checklist.json
#
# wiring-checklist.json format:
# [
#   { "file": "src/index.ts", "pattern": "import.*myModule", "description": "index.ts imports myModule" },
#   { "file": "Dockerfile", "pattern": "COPY.*dist", "description": "Dockerfile copies dist" }
# ]
#
# Exit 0 = all wiring verified, non-zero = missing wiring points

set -u

CHECKLIST="${1:-wiring-checklist.json}"
PROJECT_PATH="${2:-$(pwd)}"

cd "$PROJECT_PATH" || exit 1

FAILURES=0
TOTAL=0

if [ ! -f "$CHECKLIST" ]; then
  echo "No wiring checklist found at $CHECKLIST — skipping"
  exit 0
fi

# Validate JSON
if ! jq empty "$CHECKLIST" 2>/dev/null; then
  echo "ERROR: $CHECKLIST is not valid JSON"
  exit 1
fi

COUNT=$(jq 'length' "$CHECKLIST")
if [ "$COUNT" -eq 0 ]; then
  echo "Wiring checklist is empty — skipping"
  exit 0
fi

echo "=== WIRING CHECK ==="
echo "Checklist: $CHECKLIST ($COUNT items)"
echo ""

# Check each item
for i in $(seq 0 $(($COUNT - 1))); do
  FILE=$(jq -r ".[$i].file" "$CHECKLIST")
  PATTERN=$(jq -r ".[$i].pattern" "$CHECKLIST")
  DESC=$(jq -r ".[$i].description // \"$FILE contains $PATTERN\"" "$CHECKLIST")
  TOTAL=$((TOTAL + 1))

  if [ ! -f "$FILE" ]; then
    echo "FAIL: $DESC"
    echo "      File not found: $FILE"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  if grep -qE "$PATTERN" "$FILE" 2>/dev/null; then
    echo "PASS: $DESC"
  else
    echo "FAIL: $DESC"
    echo "      Pattern '$PATTERN' not found in $FILE"
    FAILURES=$((FAILURES + 1))
  fi
done

echo ""
echo "=== WIRING SUMMARY ==="
echo "Checked: $TOTAL | Passed: $(($TOTAL - $FAILURES)) | Failed: $FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "ALL WIRING VERIFIED"
  exit 0
else
  echo "WIRING INCOMPLETE: $FAILURES point(s) not connected"
  exit 1
fi
