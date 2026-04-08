#!/usr/bin/env bash
# dispatch-multi.sh — Dependency-aware multi-ticket dispatch with Linear integration.
#
# Usage: ./scripts/dispatch-multi.sh <repo-path> <ticket-id-1> <ticket-id-2> ...
#
# Looks up each ticket in Linear, discovers blocking relations, topologically
# sorts them, and dispatches independent tickets in parallel while queuing
# dependent tickets after their blockers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOUSTON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# ---------------------------------------------------------------------------
# Source Linear helpers (graceful if missing or keys not set)
# ---------------------------------------------------------------------------
LINEAR_AVAILABLE=false
if [[ -f "$HOUSTON_DIR/pipeline/linear.sh" ]]; then
  source "$HOUSTON_DIR/pipeline/linear.sh"
  if [[ -n "${LINEAR_API_KEY:-}" ]] || [[ -n "${SKYNER_LINEAR_API_KEY:-}" ]]; then
    LINEAR_AVAILABLE=true
  fi
fi

# ---------------------------------------------------------------------------
# Data structures (bash associative arrays)
# ---------------------------------------------------------------------------
declare -A TICKET_TITLE        # TICKET_ID -> title
declare -A TICKET_KEY_ENV      # TICKET_ID -> matched api key env var
declare -A BLOCKED_BY          # TICKET_ID -> space-separated list of blockers
declare -A BLOCKS              # TICKET_ID -> space-separated list of tickets it blocks
FOUND_TICKETS=()               # Tickets successfully looked up
MISSING_TICKETS=()             # Tickets not found in Linear

echo ""
echo "Houston Multi-Ticket Dispatch"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ---------------------------------------------------------------------------
# Phase 1: Look up tickets and dependencies in Linear
# ---------------------------------------------------------------------------
if $LINEAR_AVAILABLE; then
  echo "Phase 1: Looking up tickets in Linear..."
  for ticket in "${TICKETS[@]}"; do
    result=""
    if result=$(linear_find_ticket "$ticket" 2>/dev/null); then
      title=$(echo "$result" | jq -r '.data.issueSearch.nodes[0].title // "untitled"')
      key_env=$(echo "$result" | jq -r '.matched_key_env // "LINEAR_API_KEY"')
      TICKET_TITLE["$ticket"]="$title"
      TICKET_KEY_ENV["$ticket"]="$key_env"
      FOUND_TICKETS+=("$ticket")
    else
      echo "  ⚠ $ticket — not found in Linear, will dispatch without dependency info"
      MISSING_TICKETS+=("$ticket")
      FOUND_TICKETS+=("$ticket")
      TICKET_TITLE["$ticket"]="(unknown)"
      TICKET_KEY_ENV["$ticket"]=""
    fi
  done

  echo "  Found ${#FOUND_TICKETS[@]} ticket(s)"
  echo ""

  echo "Phase 1b: Checking dependencies..."
  for ticket in "${FOUND_TICKETS[@]}"; do
    key_env="${TICKET_KEY_ENV[$ticket]:-LINEAR_API_KEY}"
    [[ -z "$key_env" ]] && continue

    deps=""
    if deps=$(linear_get_dependencies "$ticket" "$key_env" 2>/dev/null); then
      # Parse blocking relations — look for tickets in our dispatch list
      while IFS= read -r dep_id; do
        [[ -z "$dep_id" ]] && continue
        # Only care about dependencies within our ticket list
        for other in "${TICKETS[@]}"; do
          if [[ "$dep_id" == "$other" ]]; then
            BLOCKED_BY["$ticket"]="${BLOCKED_BY[$ticket]:-} $dep_id"
            BLOCKS["$dep_id"]="${BLOCKS[$dep_id]:-} $ticket"
          fi
        done
      done < <(echo "$deps" | jq -r '.[] | select(.type == "blocked_by" or .type == "is_blocked_by" or .type == "depends_on") | .identifier' 2>/dev/null)

      # Also check the inverse: if this ticket blocks others in our list
      while IFS= read -r blocked_id; do
        [[ -z "$blocked_id" ]] && continue
        for other in "${TICKETS[@]}"; do
          if [[ "$blocked_id" == "$other" ]]; then
            BLOCKED_BY["$other"]="${BLOCKED_BY[$other]:-} $ticket"
            BLOCKS["$ticket"]="${BLOCKS[$ticket]:-} $other"
          fi
        done
      done < <(echo "$deps" | jq -r '.[] | select(.type == "blocks") | .identifier' 2>/dev/null)
    fi
  done
  echo ""
else
  echo "Phase 1: Linear API not available — skipping dependency check"
  for ticket in "${TICKETS[@]}"; do
    FOUND_TICKETS+=("$ticket")
    TICKET_TITLE["$ticket"]="(no Linear)"
  done
  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 2: Topological sort — separate independent from dependent
# ---------------------------------------------------------------------------
INDEPENDENT=()
DEPENDENT=()

for ticket in "${FOUND_TICKETS[@]}"; do
  blockers="${BLOCKED_BY[$ticket]:-}"
  blockers="$(echo "$blockers" | xargs)"  # trim whitespace
  if [[ -z "$blockers" ]]; then
    INDEPENDENT+=("$ticket")
  else
    DEPENDENT+=("$ticket")
  fi
done

# ---------------------------------------------------------------------------
# Print ticket table
# ---------------------------------------------------------------------------
echo "Tickets:"
for ticket in "${FOUND_TICKETS[@]}"; do
  title="${TICKET_TITLE[$ticket]:-}"
  blockers="${BLOCKED_BY[$ticket]:-}"
  blockers="$(echo "$blockers" | xargs)"
  line="  $ticket"
  [[ -n "$title" ]] && line="$line  \"$title\""
  [[ -n "$blockers" ]] && line="$line  <- blocked by $blockers"
  echo "$line"
done
echo ""

# ---------------------------------------------------------------------------
# Print dependency graph
# ---------------------------------------------------------------------------
has_deps=false
for ticket in "${!BLOCKS[@]}"; do
  targets="${BLOCKS[$ticket]:-}"
  targets="$(echo "$targets" | xargs)"
  if [[ -n "$targets" ]]; then
    has_deps=true
    break
  fi
done

if $has_deps; then
  echo "Dependency Graph:"
  for ticket in "${!BLOCKS[@]}"; do
    targets="$(echo "${BLOCKS[$ticket]}" | xargs)"
    [[ -z "$targets" ]] && continue
    for t in $targets; do
      echo "  $ticket -> $t"
    done
  done
  echo ""
fi

# ---------------------------------------------------------------------------
# Print launch order
# ---------------------------------------------------------------------------
echo "Launch Order:"
step=1
if [[ ${#INDEPENDENT[@]} -gt 0 ]]; then
  echo "  $step. ${INDEPENDENT[*]}  (parallel)"
  step=$((step + 1))
fi
for ticket in "${DEPENDENT[@]}"; do
  blockers="$(echo "${BLOCKED_BY[$ticket]}" | xargs)"
  echo "  $step. $ticket  (after $blockers)"
  step=$((step + 1))
done
echo ""

# ---------------------------------------------------------------------------
# Phase 3: Dispatch
# ---------------------------------------------------------------------------
echo "Dispatching..."
LAUNCHED=0
FAILED=0
QUEUED=0

# Launch independent tickets (parallel — dispatch.sh uses --no-wait)
for ticket in "${INDEPENDENT[@]}"; do
  session="$(echo "$ticket" | tr '[:upper:]' '[:lower:]')"
  if "${SCRIPT_DIR}/dispatch.sh" "$ticket" "$REPO_PATH" 2>/dev/null; then
    echo "  ✓ $ticket — session: $session"
    LAUNCHED=$((LAUNCHED + 1))
  else
    echo "  ✗ $ticket — failed to dispatch" >&2
    FAILED=$((FAILED + 1))
  fi
done

# Launch dependent tickets (they still dispatch but are noted as queued)
for ticket in "${DEPENDENT[@]}"; do
  session="$(echo "$ticket" | tr '[:upper:]' '[:lower:]')"
  blockers="$(echo "${BLOCKED_BY[$ticket]}" | xargs)"
  if "${SCRIPT_DIR}/dispatch.sh" "$ticket" "$REPO_PATH" 2>/dev/null; then
    echo "  ⏳ $ticket — queued (waiting for $blockers)"
    LAUNCHED=$((LAUNCHED + 1))
    QUEUED=$((QUEUED + 1))
  else
    echo "  ✗ $ticket — failed to dispatch" >&2
    FAILED=$((FAILED + 1))
  fi
done

# ---------------------------------------------------------------------------
# Phase 4: Summary
# ---------------------------------------------------------------------------
TOTAL=${#FOUND_TICKETS[@]}
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$LAUNCHED ticket(s) dispatched ($QUEUED queued). Failed: $FAILED. Total: $TOTAL"
echo "Monitor: agent-deck"
