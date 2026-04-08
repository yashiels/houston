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
# Data structures — parallel indexed arrays (bash 3.2 compatible)
# ---------------------------------------------------------------------------
TICKET_TITLE_KEYS=()
TICKET_TITLE_VALS=()
TICKET_KEY_ENV_KEYS=()
TICKET_KEY_ENV_VALS=()
BLOCKED_BY_KEYS=()
BLOCKED_BY_VALS=()
BLOCKS_KEYS=()
BLOCKS_VALS=()
FOUND_TICKETS=()               # Tickets successfully looked up
MISSING_TICKETS=()             # Tickets not found in Linear

# Per-map get/set helpers (bash 3.2 has no namerefs)
_ticket_title_get() {
  local key="$1"
  for _i in "${!TICKET_TITLE_KEYS[@]}"; do
    if [[ "${TICKET_TITLE_KEYS[$_i]}" == "$key" ]]; then echo "${TICKET_TITLE_VALS[$_i]}"; return; fi
  done
  echo ""
}
_ticket_title_set() {
  local key="$1" val="$2"
  for _i in "${!TICKET_TITLE_KEYS[@]}"; do
    if [[ "${TICKET_TITLE_KEYS[$_i]}" == "$key" ]]; then TICKET_TITLE_VALS[$_i]="$val"; return; fi
  done
  TICKET_TITLE_KEYS+=("$key"); TICKET_TITLE_VALS+=("$val")
}

_ticket_key_env_get() {
  local key="$1"
  for _i in "${!TICKET_KEY_ENV_KEYS[@]}"; do
    if [[ "${TICKET_KEY_ENV_KEYS[$_i]}" == "$key" ]]; then echo "${TICKET_KEY_ENV_VALS[$_i]}"; return; fi
  done
  echo ""
}
_ticket_key_env_set() {
  local key="$1" val="$2"
  for _i in "${!TICKET_KEY_ENV_KEYS[@]}"; do
    if [[ "${TICKET_KEY_ENV_KEYS[$_i]}" == "$key" ]]; then TICKET_KEY_ENV_VALS[$_i]="$val"; return; fi
  done
  TICKET_KEY_ENV_KEYS+=("$key"); TICKET_KEY_ENV_VALS+=("$val")
}

_blocked_by_get() {
  local key="$1"
  for _i in "${!BLOCKED_BY_KEYS[@]}"; do
    if [[ "${BLOCKED_BY_KEYS[$_i]}" == "$key" ]]; then echo "${BLOCKED_BY_VALS[$_i]}"; return; fi
  done
  echo ""
}
_blocked_by_set() {
  local key="$1" val="$2"
  for _i in "${!BLOCKED_BY_KEYS[@]}"; do
    if [[ "${BLOCKED_BY_KEYS[$_i]}" == "$key" ]]; then BLOCKED_BY_VALS[$_i]="$val"; return; fi
  done
  BLOCKED_BY_KEYS+=("$key"); BLOCKED_BY_VALS+=("$val")
}

_blocks_get() {
  local key="$1"
  for _i in "${!BLOCKS_KEYS[@]}"; do
    if [[ "${BLOCKS_KEYS[$_i]}" == "$key" ]]; then echo "${BLOCKS_VALS[$_i]}"; return; fi
  done
  echo ""
}
_blocks_set() {
  local key="$1" val="$2"
  for _i in "${!BLOCKS_KEYS[@]}"; do
    if [[ "${BLOCKS_KEYS[$_i]}" == "$key" ]]; then BLOCKS_VALS[$_i]="$val"; return; fi
  done
  BLOCKS_KEYS+=("$key"); BLOCKS_VALS+=("$val")
}

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
      _ticket_title_set "$ticket" "$title"
      _ticket_key_env_set "$ticket" "$key_env"
      FOUND_TICKETS+=("$ticket")
    else
      echo "  ⚠ $ticket — not found in Linear, will dispatch without dependency info"
      MISSING_TICKETS+=("$ticket")
      FOUND_TICKETS+=("$ticket")
      _ticket_title_set "$ticket" "(unknown)"
      _ticket_key_env_set "$ticket" ""
    fi
  done

  echo "  Found ${#FOUND_TICKETS[@]} ticket(s)"
  echo ""

  echo "Phase 1b: Checking dependencies..."
  for ticket in "${FOUND_TICKETS[@]}"; do
    key_env="$(_ticket_key_env_get "$ticket")"
    key_env="${key_env:-LINEAR_API_KEY}"
    [[ -z "$key_env" ]] && continue

    deps=""
    if deps=$(linear_get_dependencies "$ticket" "$key_env" 2>/dev/null); then
      # Parse blocking relations — look for tickets in our dispatch list
      while IFS= read -r dep_id; do
        [[ -z "$dep_id" ]] && continue
        # Only care about dependencies within our ticket list
        for other in "${TICKETS[@]}"; do
          if [[ "$dep_id" == "$other" ]]; then
            _blocked_by_set "$ticket" "$(_blocked_by_get "$ticket") $dep_id"
            _blocks_set "$dep_id" "$(_blocks_get "$dep_id") $ticket"
          fi
        done
      done < <(echo "$deps" | jq -r '.[] | select(.type == "blocked_by" or .type == "is_blocked_by" or .type == "depends_on") | .identifier' 2>/dev/null)

      # Also check the inverse: if this ticket blocks others in our list
      while IFS= read -r blocked_id; do
        [[ -z "$blocked_id" ]] && continue
        for other in "${TICKETS[@]}"; do
          if [[ "$blocked_id" == "$other" ]]; then
            _blocked_by_set "$other" "$(_blocked_by_get "$other") $ticket"
            _blocks_set "$ticket" "$(_blocks_get "$ticket") $other"
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
    _ticket_title_set "$ticket" "(no Linear)"
  done
  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 2: Topological sort — separate independent from dependent
# ---------------------------------------------------------------------------
INDEPENDENT=()
DEPENDENT=()

for ticket in "${FOUND_TICKETS[@]}"; do
  blockers="$(_blocked_by_get "$ticket")"
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
  title="$(_ticket_title_get "$ticket")"
  blockers="$(_blocked_by_get "$ticket")"
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
for ticket in "${BLOCKS_KEYS[@]}"; do
  targets="$(_blocks_get "$ticket")"
  targets="$(echo "$targets" | xargs)"
  if [[ -n "$targets" ]]; then
    has_deps=true
    break
  fi
done

if $has_deps; then
  echo "Dependency Graph:"
  for ticket in "${BLOCKS_KEYS[@]}"; do
    targets="$(_blocks_get "$ticket")"
    targets="$(echo "$targets" | xargs)"
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
  blockers="$(_blocked_by_get "$ticket")"
  blockers="$(echo "$blockers" | xargs)"
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
  blockers="$(_blocked_by_get "$ticket")"
  blockers="$(echo "$blockers" | xargs)"
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
