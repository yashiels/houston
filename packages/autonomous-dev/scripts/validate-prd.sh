#!/bin/bash
# validate-prd.sh — Validate prd.json structure using jq
# Usage: ./scripts/validate-prd.sh [path/to/prd.json]
# Exit 0 = valid, non-zero = validation errors found

set -uo pipefail

PRD_FILE="${1:-prd.json}"
ERRORS=0

if [ ! -f "$PRD_FILE" ]; then
  echo "ERROR: File not found: $PRD_FILE"
  exit 1
fi

if ! jq empty "$PRD_FILE" 2>/dev/null; then
  echo "ERROR: Invalid JSON in $PRD_FILE"
  exit 1
fi

check() {
  local description="$1"
  local jq_expr="$2"
  local expected="${3:-true}"

  result=$(jq -r "$jq_expr" "$PRD_FILE" 2>/dev/null)
  if [ "$result" = "$expected" ]; then
    echo "OK: $description"
  else
    echo "FAIL: $description (got: $result)"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "Validating: $PRD_FILE"
echo ""

# Top-level required fields
check "Has .name" 'has("name")' "true"
check "Has .branchName" 'has("branchName")' "true"
check "Has .phases array" 'has("phases") and (.phases | type) == "array"' "true"
check "Has .userStories array" 'has("userStories") and (.userStories | type) == "array"' "true"
check "Has at least one phase" '(.phases | length) > 0' "true"
check "Has at least one story" '(.userStories | length) > 0' "true"

# Branch name format (no spaces, valid git branch)
check "branchName has no spaces" '(.branchName | test(" ")) | not' "true"

# Phase structure
PHASE_COUNT=$(jq '.phases | length' "$PRD_FILE")
echo ""
echo "Checking $PHASE_COUNT phases..."

for i in $(seq 0 $((PHASE_COUNT - 1))); do
  PHASE_ID=$(jq -r ".phases[$i].id // \"MISSING\"" "$PRD_FILE")
  check "Phase[$i] has .id" ".phases[$i] | has(\"id\")" "true"
  check "Phase[$i] ($PHASE_ID) has .name" ".phases[$i] | has(\"name\")" "true"
  check "Phase[$i] ($PHASE_ID) has .description" ".phases[$i] | has(\"description\")" "true"
done

# Story structure
STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE")
echo ""
echo "Checking $STORY_COUNT stories..."

for i in $(seq 0 $((STORY_COUNT - 1))); do
  STORY_ID=$(jq -r ".userStories[$i].id // \"MISSING\"" "$PRD_FILE")

  check "Story[$i] ($STORY_ID) has .id" ".userStories[$i] | has(\"id\")" "true"
  check "Story[$i] ($STORY_ID) has .phase" ".userStories[$i] | has(\"phase\")" "true"
  check "Story[$i] ($STORY_ID) has .title" ".userStories[$i] | has(\"title\")" "true"
  check "Story[$i] ($STORY_ID) has .description" ".userStories[$i] | has(\"description\")" "true"
  check "Story[$i] ($STORY_ID) has .acceptanceCriteria" ".userStories[$i] | has(\"acceptanceCriteria\")" "true"
  check "Story[$i] ($STORY_ID) has non-empty acceptanceCriteria" "(.userStories[$i].acceptanceCriteria | length) > 0" "true"
  check "Story[$i] ($STORY_ID) has .estimatedMinutes" ".userStories[$i] | has(\"estimatedMinutes\")" "true"
  check "Story[$i] ($STORY_ID) has .passes field" ".userStories[$i] | has(\"passes\")" "true"

  # Verify story references a valid phase
  STORY_PHASE=$(jq -r ".userStories[$i].phase" "$PRD_FILE")
  VALID_PHASE=$(jq -r "[.phases[].id] | contains([\"$STORY_PHASE\"])" "$PRD_FILE")
  if [ "$VALID_PHASE" = "true" ]; then
    echo "OK: Story[$i] ($STORY_ID) phase '$STORY_PHASE' exists"
  else
    echo "FAIL: Story[$i] ($STORY_ID) references non-existent phase '$STORY_PHASE'"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check for duplicate story IDs
DUPLICATE_IDS=$(jq -r '[.userStories[].id] | group_by(.) | map(select(length > 1)) | .[] | .[0]' "$PRD_FILE" 2>/dev/null || true)
if [ -n "$DUPLICATE_IDS" ]; then
  echo "FAIL: Duplicate story IDs found: $DUPLICATE_IDS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK: No duplicate story IDs"
fi

# Summary
echo ""
if [ "$ERRORS" -eq 0 ]; then
  STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE")
  PHASE_COUNT=$(jq '.phases | length' "$PRD_FILE")
  echo "VALID: $PRD_FILE ($PHASE_COUNT phases, $STORY_COUNT stories)"
  exit 0
else
  echo "INVALID: $ERRORS error(s) found in $PRD_FILE"
  exit 1
fi
