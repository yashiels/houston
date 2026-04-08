#!/usr/bin/env bash
# status.sh — Show running Houston pipelines.
#
# Usage: ./scripts/status.sh

set -euo pipefail

RUNS_DIR="$HOME/.houston/runs"

# ---------------------------------------------------------------------------
# Check for runs directory
# ---------------------------------------------------------------------------
if [[ ! -d "$RUNS_DIR" ]]; then
  echo "No active pipelines."
  exit 0
fi

# Collect run directories
shopt -s nullglob
run_dirs=("$RUNS_DIR"/*)
shopt -u nullglob

if [[ ${#run_dirs[@]} -eq 0 ]]; then
  echo "No active pipelines."
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: relative time
# ---------------------------------------------------------------------------
relative_time() {
  local timestamp="$1"
  local now_epoch updated_epoch diff

  now_epoch="$(date +%s)"

  # macOS and GNU date differ — try both
  if updated_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null)"; then
    : # macOS succeeded
  elif updated_epoch="$(date -d "$timestamp" +%s 2>/dev/null)"; then
    : # GNU date succeeded
  else
    echo "$timestamp"
    return
  fi

  diff=$(( now_epoch - updated_epoch ))

  if [[ $diff -lt 60 ]]; then
    echo "${diff}s ago"
  elif [[ $diff -lt 3600 ]]; then
    echo "$(( diff / 60 ))m ago"
  elif [[ $diff -lt 86400 ]]; then
    echo "$(( diff / 3600 ))h ago"
  else
    echo "$(( diff / 86400 ))d ago"
  fi
}

# ---------------------------------------------------------------------------
# Build table
# ---------------------------------------------------------------------------
count=0
rows=()

for dir in "${run_dirs[@]}"; do
  state_file="$dir/state.json"
  [[ -f "$state_file" ]] || continue

  ticket_id="$(jq -r '.ticket_id // "?"' "$state_file")"
  profile="$(jq -r '.profile // "?"' "$state_file")"
  current_step="$(jq -r '.current_step // "?"' "$state_file")"
  mode="$(jq -r '.mode // "?"' "$state_file")"
  updated_at="$(jq -r '.updated_at // ""' "$state_file")"

  if [[ -n "$updated_at" ]]; then
    updated="$(relative_time "$updated_at")"
  else
    updated="?"
  fi

  rows+=("$(printf "%-14s%-11s%-14s%-13s%s" "$ticket_id" "$profile" "$current_step" "$mode" "$updated")")
  count=$((count + 1))
done

if [[ $count -eq 0 ]]; then
  echo "No active pipelines."
  exit 0
fi

# ---------------------------------------------------------------------------
# Print table
# ---------------------------------------------------------------------------
echo "Houston Pipeline Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-14s%-11s%-14s%-13s%s\n" "TICKET" "PROFILE" "STEP" "MODE" "UPDATED"

for row in "${rows[@]}"; do
  echo "$row"
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$count pipeline(s) running"
