#!/usr/bin/env bash
# dispatch-multi.sh — Launch multiple ticket pipelines in parallel.
#
# Usage: ./scripts/dispatch-multi.sh <repo-path> <ticket-id-1> <ticket-id-2> ...
#
# Thin wrapper around dispatch.sh. Real dependency logic will be added in Phase 6.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <repo-path> <ticket-id-1> [ticket-id-2] ..." >&2
  exit 1
fi

REPO_PATH="$1"
shift

TICKETS=("$@")
LAUNCHED=0
FAILED=0

echo "Houston Multi-Dispatch"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Repo:    $REPO_PATH"
echo "Tickets: ${TICKETS[*]}"
echo ""

# ---------------------------------------------------------------------------
# Launch each ticket
# ---------------------------------------------------------------------------
for ticket in "${TICKETS[@]}"; do
  echo "--- Dispatching $ticket ---"
  if "${SCRIPT_DIR}/dispatch.sh" "$ticket" "$REPO_PATH"; then
    LAUNCHED=$((LAUNCHED + 1))
  else
    echo "  Failed to dispatch $ticket" >&2
    FAILED=$((FAILED + 1))
  fi
  echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dispatched: $LAUNCHED | Failed: $FAILED | Total: ${#TICKETS[@]}"
