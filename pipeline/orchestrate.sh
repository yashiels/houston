#!/usr/bin/env bash
# orchestrate.sh — State machine that drives the Houston development pipeline.
# Called repeatedly with subcommands. Each call reads state from disk,
# does work, updates state, and outputs a JSON action to stdout.
#
# Usage:
#   orchestrate.sh next <ticket-id>
#   orchestrate.sh complete <ticket-id> <step> [status] [data]
#   orchestrate.sh gate-response <ticket-id> <CONTINUE|STOP> [instructions]
#   orchestrate.sh status <ticket-id>
#
# All output is JSON to stdout. Errors/logs go to stderr or log files.

set -u

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
HOUSTON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

json_get() {
  jq -r "$1 // empty" "$STATE_FILE" 2>/dev/null
}

json_set() {
  local expr="$1"
  local tmp
  tmp=$(mktemp)
  if jq "$expr" "$STATE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    emit_error "Failed to update state: $expr"
    return 1
  fi
}

log_step() {
  local level="$1" msg="$2"
  mkdir -p "$RUN_DIR/logs" 2>/dev/null || true
  echo "[$(now)] ${level}: ${msg}" >> "$RUN_DIR/logs/orchestrate.log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# JSON emitters — these print to stdout and exit
# ---------------------------------------------------------------------------
emit_json() {
  echo "$1"
  exit 0
}

emit_error() {
  local msg="$1"
  echo "$msg" >&2
  jq -n --arg message "$msg" '{"action":"error","message":$message}'
  exit 1
}

emit_spawn() {
  local step="$1" template="$2"
  local ticket_id repo_path profile platform cli branch
  ticket_id="$(json_get '.ticket_id')"
  repo_path="$(json_get '.repo_path')"
  profile="$(json_get '.profile')"
  platform="$(json_get '.platform')"
  cli="$(json_get '.cli')"
  branch="$(json_get '.branch')"

  # For phase steps, include phase number in context
  local extra_context=""
  if [[ "$step" =~ ^PHASE-([0-9]+)$ ]]; then
    extra_context="$(printf ',"phase_number":%s' "${BASH_REMATCH[1]}")"
  fi

  jq -n \
    --arg action "spawn" \
    --arg step "$step" \
    --arg template "$template" \
    --arg ticket_id "$ticket_id" \
    --arg run_dir "$RUN_DIR" \
    --arg repo_path "$repo_path" \
    --arg profile "$profile" \
    --arg platform "$platform" \
    --arg cli "$cli" \
    --arg branch "$branch" \
    --argjson extra_ctx "{\"placeholder\":0${extra_context}}" \
    '{
      action: $action,
      step: $step,
      template: $template,
      context: ({
        ticket_id: $ticket_id,
        run_dir: $run_dir,
        repo_path: $repo_path,
        profile: $profile,
        platform: $platform,
        cli: $cli,
        branch: $branch
      } + ($extra_ctx | del(.placeholder)))
    }'
}

emit_gate() {
  local step="$1" message="$2"
  local mode
  mode="$(json_get '.mode')"
  jq -n \
    --arg action "gate" \
    --arg step "$step" \
    --arg message "$message" \
    --arg mode "$mode" \
    '{ action: $action, step: $step, message: $message, mode: $mode }'
}

emit_complete_action() {
  local ticket_id
  ticket_id="$(json_get '.ticket_id')"
  jq -n \
    --arg action "complete" \
    --arg ticket_id "$ticket_id" \
    --arg message "Pipeline complete" \
    '{ action: $action, ticket_id: $ticket_id, message: $message }'
}

emit_blocked() {
  local step="$1" reason="$2"
  jq -n \
    --arg action "blocked" \
    --arg step "$step" \
    --arg reason "$reason" \
    '{ action: $action, step: $step, reason: $reason }'
}

emit_status() {
  local ticket_id current_step mode steps_completed created_at updated_at
  ticket_id="$(json_get '.ticket_id')"
  current_step="$(json_get '.current_step')"
  mode="$(json_get '.mode')"
  created_at="$(json_get '.created_at')"
  updated_at="$(json_get '.updated_at')"

  jq -n \
    --arg action "status" \
    --arg ticket_id "$ticket_id" \
    --arg current_step "$current_step" \
    --arg mode "$mode" \
    --argjson steps_completed "$(jq '.steps_completed' "$STATE_FILE")" \
    --arg created_at "$created_at" \
    --arg updated_at "$updated_at" \
    '{
      action: $action,
      ticket_id: $ticket_id,
      current_step: $current_step,
      mode: $mode,
      steps_completed: $steps_completed,
      created_at: $created_at,
      updated_at: $updated_at
    }'
}

# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------
advance_step() {
  local from="$1"
  json_set "(.steps_completed += [\"${from}\"]) | .updated_at = \"$(now)\""
}

set_current_step() {
  local step="$1"
  json_set ".current_step = \"${step}\" | .updated_at = \"$(now)\""
}

# Return the next step given the current step
get_next_step() {
  local current="$1"

  case "$current" in
    init)              echo "detect-context" ;;
    detect-context)    echo "detect-project" ;;
    detect-project)    echo "pull-latest" ;;
    pull-latest)       echo "branch-create" ;;
    branch-create)     echo "baseline" ;;
    baseline)          echo "RESEARCH" ;;
    RESEARCH)          echo "GRILL-RESEARCH" ;;
    GRILL-RESEARCH)    echo "research-review" ;;
    research-review)   echo "PLAN" ;;
    PLAN)              echo "validate-prd" ;;
    validate-prd)      echo "GRILL-PLAN" ;;
    GRILL-PLAN)        echo "plan-review" ;;
    plan-review)       echo "PRE-FLIGHT" ;;
    PRE-FLIGHT)        echo "$(get_first_phase)" ;;
    FINAL-REVIEW)      echo "CODE-SIMPLIFY" ;;
    CODE-SIMPLIFY)     echo "PR-CREATE" ;;
    PR-CREATE)         echo "CI-MONITOR" ;;
    CI-MONITOR)        echo "LINEAR-UPDATE" ;;
    LINEAR-UPDATE)     echo "complete" ;;
    complete)          echo "complete" ;;
    *)
      # Handle PHASE-N and phase-N-quality-gate
      if [[ "$current" =~ ^PHASE-([0-9]+)$ ]]; then
        local n="${BASH_REMATCH[1]}"
        echo "phase-${n}-quality-gate"
      elif [[ "$current" =~ ^phase-([0-9]+)-quality-gate$ ]]; then
        local n="${BASH_REMATCH[1]}"
        local next_phase=$((n + 1))
        local total_phases
        total_phases="$(get_total_phases)"
        if [[ "$next_phase" -gt "$total_phases" ]]; then
          echo "FINAL-REVIEW"
        else
          echo "PHASE-${next_phase}"
        fi
      else
        echo ""
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Phase helpers
# ---------------------------------------------------------------------------
get_total_phases() {
  local prd_file="$RUN_DIR/prd.json"
  if [[ -f "$prd_file" ]]; then
    local count
    count="$(jq '.phases | length' "$prd_file" 2>/dev/null || echo "0")"
    if [[ "$count" -gt 0 ]]; then
      echo "$count"
      return
    fi
  fi
  # Default: 1 phase if no prd.json
  echo "1"
}

get_first_phase() {
  echo "PHASE-1"
}

# ---------------------------------------------------------------------------
# Step type classification
# ---------------------------------------------------------------------------
is_mechanical_step() {
  local step="$1"
  case "$step" in
    init|detect-context|detect-project|pull-latest|branch-create|baseline)
      return 0 ;;
    validate-prd|PRE-FLIGHT|PR-CREATE|LINEAR-UPDATE)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

is_ai_step() {
  local step="$1"
  case "$step" in
    RESEARCH|GRILL-RESEARCH|PLAN|GRILL-PLAN|FINAL-REVIEW|CODE-SIMPLIFY|CI-MONITOR)
      return 0 ;;
    *)
      # Phase steps and quality gates are AI steps
      if [[ "$step" =~ ^PHASE-[0-9]+$ ]]; then
        return 0
      fi
      if [[ "$step" =~ ^phase-[0-9]+-quality-gate$ ]]; then
        return 0
      fi
      return 1
      ;;
  esac
}

is_gate_step() {
  local step="$1"
  case "$step" in
    research-review|plan-review) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Get the AI template for a step
# ---------------------------------------------------------------------------
get_template_for_step() {
  local step="$1"
  case "$step" in
    RESEARCH)           echo "researcher.md" ;;
    GRILL-RESEARCH)     echo "grill-research.md" ;;
    PLAN)               echo "planner.md" ;;
    GRILL-PLAN)         echo "grill-plan.md" ;;
    FINAL-REVIEW)       echo "final-review.md" ;;
    CODE-SIMPLIFY)      echo "code-simplify.md" ;;
    CI-MONITOR)         echo "ci-monitor.md" ;;
    *)
      if [[ "$step" =~ ^PHASE-[0-9]+$ ]]; then
        echo "phase-supervisor.md"
      elif [[ "$step" =~ ^phase-[0-9]+-quality-gate$ ]]; then
        echo "quality-gate.md"
      else
        echo ""
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Get gate message
# ---------------------------------------------------------------------------
get_gate_message() {
  local step="$1"
  case "$step" in
    research-review)
      echo "Research complete. Review findings at ${RUN_DIR}/research/findings.md"
      ;;
    plan-review)
      echo "Plan complete. Review PRD at ${RUN_DIR}/prd.json"
      ;;
    *)
      echo "Gate reached at step: ${step}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Execute a mechanical step (returns 0 on success, 1 on failure)
# ---------------------------------------------------------------------------
execute_mechanical_step() {
  local step="$1"
  log_step "INFO" "Executing mechanical step: ${step}"

  case "$step" in
    init)
      # Just advance
      return 0
      ;;
    detect-context)
      # Already done by init-pipeline.sh
      return 0
      ;;
    detect-project)
      # Already done by init-pipeline.sh
      return 0
      ;;
    pull-latest)
      local repo_path
      repo_path="$(json_get '.repo_path')"
      if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        (cd "$repo_path" && git pull --rebase 2>/dev/null || true)
        log_step "INFO" "Pulled latest in ${repo_path}"
      else
        log_step "WARN" "Repo path not found: ${repo_path}"
      fi
      return 0
      ;;
    branch-create)
      local repo_path branch
      repo_path="$(json_get '.repo_path')"
      branch="$(json_get '.branch')"
      if [[ -n "$repo_path" && -d "$repo_path" && -n "$branch" ]]; then
        (cd "$repo_path" && git checkout -b "$branch" 2>/dev/null || git checkout "$branch" 2>/dev/null || true)
        log_step "INFO" "Checked out branch: ${branch}"
      else
        log_step "WARN" "Cannot create branch: repo_path=${repo_path}, branch=${branch}"
      fi
      return 0
      ;;
    baseline)
      local repo_path
      repo_path="$(json_get '.repo_path')"
      if [[ -x "${SCRIPT_DIR}/detect-project.sh" && -n "$repo_path" && -d "$repo_path" ]]; then
        "${SCRIPT_DIR}/detect-project.sh" "$repo_path" > "$RUN_DIR/baseline.json" 2>/dev/null || true
        log_step "INFO" "Saved baseline to ${RUN_DIR}/baseline.json"
      else
        log_step "WARN" "Cannot run baseline detection"
      fi
      return 0
      ;;
    validate-prd)
      if [[ -f "$RUN_DIR/prd.json" ]]; then
        log_step "INFO" "prd.json exists, validation passed"
        return 0
      else
        log_step "WARN" "prd.json not found — advancing anyway"
        return 0
      fi
      ;;
    PRE-FLIGHT)
      # Verify branch exists, deps installed — placeholder for now
      log_step "INFO" "Pre-flight check passed (placeholder)"
      return 0
      ;;
    PR-CREATE)
      # Placeholder — PR creation will come in a later phase
      log_step "INFO" "PR creation step (placeholder)"
      return 0
      ;;
    LINEAR-UPDATE)
      # Placeholder — Linear update will come in a later phase
      log_step "INFO" "Linear update step (placeholder)"
      return 0
      ;;
    *)
      log_step "ERROR" "Unknown mechanical step: ${step}"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Process the current step: execute mechanical, emit spawn/gate, or complete.
# Returns a JSON action string via stdout. For mechanical steps, chains
# through all consecutive mechanical steps before returning.
# ---------------------------------------------------------------------------
process_current_step() {
  local current_step
  current_step="$(json_get '.current_step')"

  # Terminal state
  if [[ "$current_step" == "complete" ]]; then
    emit_json "$(emit_complete_action)"
  fi

  # Gate step
  if is_gate_step "$current_step"; then
    local mode
    mode="$(json_get '.mode')"

    # In autonomous mode, skip gates
    if [[ "$mode" == "autonomous" ]]; then
      log_step "INFO" "Skipping gate ${current_step} (autonomous mode)"
      advance_step "$current_step"
      local next
      next="$(get_next_step "$current_step")"
      set_current_step "$next"
      process_current_step
      return
    fi

    # In supervised or human-assisted mode, emit gate
    local message
    message="$(get_gate_message "$current_step")"
    emit_json "$(emit_gate "$current_step" "$message")"
  fi

  # AI step
  if is_ai_step "$current_step"; then
    local template
    template="$(get_template_for_step "$current_step")"
    if [[ -z "$template" ]]; then
      emit_error "No template found for AI step: ${current_step}"
    fi
    emit_json "$(emit_spawn "$current_step" "$template")"
  fi

  # Mechanical step — execute and chain
  if is_mechanical_step "$current_step"; then
    if execute_mechanical_step "$current_step"; then
      advance_step "$current_step"
      local next
      next="$(get_next_step "$current_step")"
      if [[ -z "$next" ]]; then
        emit_error "No next step found after: ${current_step}"
      fi
      set_current_step "$next"
      # Recurse to handle the next step (chains mechanical steps)
      process_current_step
      return
    else
      emit_json "$(emit_blocked "$current_step" "Mechanical step failed: ${current_step}")"
    fi
  fi

  # Unknown step type
  emit_error "Unknown step type: ${current_step}"
}

# ---------------------------------------------------------------------------
# Subcommand: next
# ---------------------------------------------------------------------------
cmd_next() {
  local ticket_id="$1"
  RUN_DIR="$HOME/.houston/runs/${ticket_id}"
  STATE_FILE="$RUN_DIR/state.json"

  if [[ ! -f "$STATE_FILE" ]]; then
    emit_error "No state found for ticket ${ticket_id}"
  fi

  log_step "INFO" "next called for ${ticket_id}"
  process_current_step
}

# ---------------------------------------------------------------------------
# Subcommand: complete
# ---------------------------------------------------------------------------
cmd_complete() {
  local ticket_id="$1"
  local step="$2"
  local status="${3:-success}"
  local data="${4:-}"

  RUN_DIR="$HOME/.houston/runs/${ticket_id}"
  STATE_FILE="$RUN_DIR/state.json"

  if [[ ! -f "$STATE_FILE" ]]; then
    emit_error "No state found for ticket ${ticket_id}"
  fi

  local current_step
  current_step="$(json_get '.current_step')"

  # Verify the step being completed matches the current step
  if [[ "$current_step" != "$step" ]]; then
    emit_error "Step mismatch: current is '${current_step}', completing '${step}'"
  fi

  log_step "INFO" "Completing step: ${step} with status: ${status}"

  # If status is failure, block
  if [[ "$status" == "failure" || "$status" == "failed" ]]; then
    local reason="Step ${step} failed"
    if [[ -n "$data" ]]; then
      reason="$data"
    fi
    emit_json "$(emit_blocked "$step" "$reason")"
  fi

  # Store completion data if provided
  if [[ -n "$data" ]]; then
    local data_file="$RUN_DIR/step-data/${step}.json"
    mkdir -p "$RUN_DIR/step-data" 2>/dev/null || true
    echo "$data" > "$data_file" 2>/dev/null || true
  fi

  # Advance to next step
  advance_step "$step"
  local next
  next="$(get_next_step "$step")"
  if [[ -z "$next" ]]; then
    emit_error "No next step found after: ${step}"
  fi
  set_current_step "$next"

  # Fall through to next logic
  process_current_step
}

# ---------------------------------------------------------------------------
# Subcommand: gate-response
# ---------------------------------------------------------------------------
cmd_gate_response() {
  local ticket_id="$1"
  local response="$2"
  local instructions="${3:-}"

  RUN_DIR="$HOME/.houston/runs/${ticket_id}"
  STATE_FILE="$RUN_DIR/state.json"

  if [[ ! -f "$STATE_FILE" ]]; then
    emit_error "No state found for ticket ${ticket_id}"
  fi

  local current_step
  current_step="$(json_get '.current_step')"

  # Verify we are at a gate
  if ! is_gate_step "$current_step"; then
    emit_error "Current step '${current_step}' is not a gate"
  fi

  log_step "INFO" "Gate response for ${current_step}: ${response}"

  case "$response" in
    CONTINUE)
      # Save instructions if provided
      if [[ -n "$instructions" ]]; then
        local instr_file="$RUN_DIR/step-data/${current_step}-instructions.txt"
        mkdir -p "$RUN_DIR/step-data" 2>/dev/null || true
        echo "$instructions" > "$instr_file"
        log_step "INFO" "Saved gate instructions to ${instr_file}"
      fi

      # Advance past the gate
      advance_step "$current_step"
      local next
      next="$(get_next_step "$current_step")"
      if [[ -z "$next" ]]; then
        emit_error "No next step found after gate: ${current_step}"
      fi
      set_current_step "$next"

      # Fall through to next logic
      process_current_step
      ;;
    STOP)
      local reason="Pipeline halted by user at gate: ${current_step}"
      if [[ -n "$instructions" ]]; then
        reason="$instructions"
      fi
      log_step "INFO" "Pipeline halted at ${current_step}: ${reason}"
      emit_json "$(emit_blocked "$current_step" "$reason")"
      ;;
    *)
      emit_error "Invalid gate response: '${response}'. Must be CONTINUE or STOP."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Subcommand: status
# ---------------------------------------------------------------------------
cmd_status() {
  local ticket_id="$1"
  RUN_DIR="$HOME/.houston/runs/${ticket_id}"
  STATE_FILE="$RUN_DIR/state.json"

  if [[ ! -f "$STATE_FILE" ]]; then
    emit_error "No state found for ticket ${ticket_id}"
  fi

  emit_json "$(emit_status)"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
main() {
  local subcommand="${1:-}"

  if [[ -z "$subcommand" ]]; then
    emit_error "Usage: orchestrate.sh <next|complete|gate-response|status> <ticket-id> [args...]"
  fi

  shift

  case "$subcommand" in
    next)
      local ticket_id="${1:-}"
      if [[ -z "$ticket_id" ]]; then
        emit_error "Usage: orchestrate.sh next <ticket-id>"
      fi
      cmd_next "$ticket_id"
      ;;
    complete)
      local ticket_id="${1:-}"
      local step="${2:-}"
      if [[ -z "$ticket_id" || -z "$step" ]]; then
        emit_error "Usage: orchestrate.sh complete <ticket-id> <step> [status] [data]"
      fi
      local status="${3:-success}"
      local data="${4:-}"
      cmd_complete "$ticket_id" "$step" "$status" "$data"
      ;;
    gate-response)
      local ticket_id="${1:-}"
      local response="${2:-}"
      if [[ -z "$ticket_id" || -z "$response" ]]; then
        emit_error "Usage: orchestrate.sh gate-response <ticket-id> <CONTINUE|STOP> [instructions]"
      fi
      local instructions="${3:-}"
      cmd_gate_response "$ticket_id" "$response" "$instructions"
      ;;
    status)
      local ticket_id="${1:-}"
      if [[ -z "$ticket_id" ]]; then
        emit_error "Usage: orchestrate.sh status <ticket-id>"
      fi
      cmd_status "$ticket_id"
      ;;
    *)
      emit_error "Unknown subcommand: '${subcommand}'. Use: next, complete, gate-response, status"
      ;;
  esac
}

main "$@"
