#!/usr/bin/env bash
# resume.sh — Restart a Houston pipeline from where it left off.
# Reads state.json, prints a human-readable summary to stderr,
# then calls orchestrate.sh next to continue execution.
#
# Usage: ./pipeline/resume.sh <ticket-id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
TICKET_ID="${1:-}"

if [[ -z "$TICKET_ID" ]]; then
  echo '{"error":"Usage: resume.sh <ticket-id>"}' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
RUN_DIR="${HOME}/.houston/runs/${TICKET_ID}"
STATE_FILE="${RUN_DIR}/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "{\"error\":\"state.json not found for ticket ${TICKET_ID}\",\"path\":\"${STATE_FILE}\"}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
CURRENT_STEP="$(jq -r '.current_step // "unknown"' "$STATE_FILE")"
MODE="$(jq -r '.mode // "unknown"' "$STATE_FILE")"
PROFILE="$(jq -r '.profile // "unknown"' "$STATE_FILE")"
CREATED_AT="$(jq -r '.created_at // "unknown"' "$STATE_FILE")"
UPDATED_AT="$(jq -r '.updated_at // "unknown"' "$STATE_FILE")"
STEPS_COMPLETED="$(jq -r '.steps_completed | length' "$STATE_FILE")"

# Total steps in the pipeline (fixed steps + dynamic phases)
# Fixed steps: init, detect-context, detect-project, pull-latest, branch-create,
#   baseline, RESEARCH, GRILL-RESEARCH, research-review, PLAN, validate-prd,
#   GRILL-PLAN, plan-review, PRE-FLIGHT, PHASE-N..., FINAL-REVIEW,
#   CODE-SIMPLIFY, PR-CREATE, CI-MONITOR, LINEAR-UPDATE, complete
# Base count without phases: 20. Each phase adds 2 (PHASE-N + quality-gate).
# Default to 1 phase (21 total) if prd.json is missing.
TOTAL_PHASES=1
if [[ -f "${RUN_DIR}/prd.json" ]]; then
  PHASE_COUNT="$(jq '.phases | length' "${RUN_DIR}/prd.json" 2>/dev/null || echo "0")"
  if [[ "$PHASE_COUNT" -gt 0 ]]; then
    TOTAL_PHASES="$PHASE_COUNT"
  fi
fi
TOTAL_STEPS=$(( 19 + TOTAL_PHASES * 2 ))

# ---------------------------------------------------------------------------
# Print summary to stderr
# ---------------------------------------------------------------------------
cat >&2 <<EOF
Houston Pipeline Resume — ${TICKET_ID}
  Profile:  ${PROFILE}
  Mode:     ${MODE}
  Step:     ${CURRENT_STEP}
  Started:  ${CREATED_AT}
  Last:     ${UPDATED_AT}
  Progress: ${STEPS_COMPLETED}/${TOTAL_STEPS} steps completed

Resuming...
EOF

# ---------------------------------------------------------------------------
# Hand off to orchestrator
# ---------------------------------------------------------------------------
exec "${SCRIPT_DIR}/orchestrate.sh" next "$TICKET_ID"
