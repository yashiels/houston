#!/usr/bin/env bash
# run-pipeline.sh — Drive the autonomous-dev pipeline loop without an LLM
#
# Calls orchestrate.sh in a loop, parses JSON actions, spawns Claude Code
# agents for each step, and handles gates/progress/errors mechanically.
#
# Usage:
#   ./scripts/run-pipeline.sh <PROJECT_PATH> [--mode autonomous] [--preset balanced]
#
# Exit codes:
#   0  Pipeline completed successfully
#   1  Fatal error or too many consecutive errors
#   2  Gate reached — human input required (writes pending-gate.json)

set -uo pipefail

# ─── Argument parsing ───

PROJECT_PATH="${1:-}"
if [ -z "$PROJECT_PATH" ]; then
  echo "Usage: run-pipeline.sh <PROJECT_PATH> [--mode autonomous] [--preset balanced]" >&2
  exit 1
fi
shift

# Resolve to absolute path
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

MODE="autonomous"
PRESET="balanced"
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)   MODE="${2:-autonomous}"; shift 2 ;;
    --preset) PRESET="${2:-balanced}"; shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ─── Directories ───

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATE="$SCRIPT_DIR/orchestrate.sh"
SPAWN_CODER="$SCRIPT_DIR/spawn-coder.sh"
AD_STATE_DIR="$PROJECT_PATH/.autonomous-dev"
STATE_FILE="$AD_STATE_DIR/state.json"
LOG_FILE="$AD_STATE_DIR/pipeline-runner.log"

# ─── Source config ───

if [ -f "$PIPELINE_DIR/config.sh" ]; then
  # shellcheck source=/dev/null
  source "$PIPELINE_DIR/config.sh"
fi

CO_AUTHOR="${AD_CO_AUTHOR:-Yashiel Sookdeo <yashiel@skyner.co.za>}"
AD_LLM_CLI="${AD_LLM_CLI:-claude}"

# ─── Logging ───

mkdir -p "$AD_STATE_DIR"

log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

log_json() {
  local label="$1" json="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[%s] %s: %s\n' "$ts" "$label" "$json" >> "$LOG_FILE"
}

# ─── Notification (fire and forget) ───

notify() {
  local msg="$1"
  openclaw system event --text "$msg" --mode now 2>/dev/null || true
}

# ─── Process management ───

SPAWNED_PIDS=()

cleanup() {
  log "Cleanup: killing spawned processes"
  for pid in "${SPAWNED_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}

trap cleanup EXIT INT TERM

# ─── Model resolution ───

resolve_model() {
  local role="$1"
  local alias=""

  if [ -f "$STATE_FILE" ]; then
    alias="$(jq -r ".models.${role} // \"sonnet\"" "$STATE_FILE" 2>/dev/null)"
  fi

  case "${alias:-sonnet}" in
    opus)   echo "claude-opus-4-6" ;;
    sonnet) echo "claude-sonnet-4-6" ;;
    haiku)  echo "claude-haiku-4-5-20251001" ;;
    *)      echo "claude-sonnet-4-6" ;;
  esac
}

# ─── Template resolution ───

resolve_template() {
  local template_path="$1"
  local full_path="$PIPELINE_DIR/$template_path"

  if [ ! -f "$full_path" ]; then
    log "WARNING: Template not found: $full_path"
    echo ""
    return 1
  fi

  local branch_name=""
  if [ -f "$STATE_FILE" ]; then
    branch_name="$(jq -r '.project.branch // "unknown"' "$STATE_FILE" 2>/dev/null)"
  fi

  local content
  content="$(cat "$full_path")"
  content="${content//__PROJECT_PATH__/$PROJECT_PATH}"
  content="${content//__CO_AUTHOR__/$CO_AUTHOR}"
  content="${content//__BRANCH_NAME__/$branch_name}"
  content="${content//__PIPELINE_DIR__/$PIPELINE_DIR}"
  content="${content//__AD_LLM_CLI__/$AD_LLM_CLI}"

  # Additional substitutions from state.json and prd.json
  if [ -f "$STATE_FILE" ]; then
    local current_phase current_story
    current_phase="$(jq -r '.currentPhase // ""' "$STATE_FILE" 2>/dev/null)"
    current_story="$(jq -r '.currentStory // ""' "$STATE_FILE" 2>/dev/null)"
    content="${content//__PHASE_ID__/$current_phase}"
    content="${content//__STORY_ID__/$current_story}"

    if [ -n "$current_phase" ] && [ -f "$PROJECT_PATH/prd.json" ]; then
      local phase_name phase_index total_phases story_count
      phase_name="$(jq -r ".phases[] | select(.id==\"$current_phase\") | .name // \"\"" "$PROJECT_PATH/prd.json" 2>/dev/null)"
      phase_index="$(jq -r "[.phases[].id] | index(\"$current_phase\") // 0" "$PROJECT_PATH/prd.json" 2>/dev/null)"
      total_phases="$(jq -r '.phases | length' "$PROJECT_PATH/prd.json" 2>/dev/null)"
      story_count="$(jq -r ".phases[] | select(.id==\"$current_phase\") | .stories | length // 0" "$PROJECT_PATH/prd.json" 2>/dev/null)"
      content="${content//__PHASE_NAME__/$phase_name}"
      content="${content//__PHASE_INDEX__/$phase_index}"
      content="${content//__TOTAL_PHASES__/$total_phases}"
      content="${content//__STORY_COUNT__/$story_count}"
    fi

    if [ -f "$PROJECT_PATH/prd.json" ]; then
      local prd_name
      prd_name="$(jq -r '.name // "unknown"' "$PROJECT_PATH/prd.json" 2>/dev/null)"
      content="${content//__PRD_NAME__/$prd_name}"
    fi
  fi

  # Issue details — use the PRD or issue file if present
  local issue_details="prd.json"
  if [ -f "$PROJECT_PATH/issue.md" ]; then
    issue_details="issue.md"
  fi
  content="${content//__ISSUE_DETAILS__/$issue_details}"

  echo "$content"
}

# ─── Orchestrate wrapper ───

run_orchestrate() {
  cd "$PROJECT_PATH" || { log "ERROR: Cannot cd to $PROJECT_PATH"; exit 1; }
  export AD_STATE_DIR="$AD_STATE_DIR"
  "$ORCHESTRATE" "$@" 2>&1
}

# ─── Wait for background process with timeout ───

wait_with_timeout() {
  local pid="$1"
  local timeout_secs="${2:-3600}"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_secs" ]; then
      log "TIMEOUT: Process $pid exceeded ${timeout_secs}s — killing"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  wait "$pid" 2>/dev/null
  return $?
}

# ─── Initialize or resume ───

if [ -f "$STATE_FILE" ]; then
  log "State file found — resuming pipeline"

  # Check if pipeline uses a worktree — if so, switch to it
  WORKTREE="$(jq -r '.project.worktree // empty' "$STATE_FILE" 2>/dev/null)"
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    log "Worktree detected: $WORKTREE — switching PROJECT_PATH"
    PROJECT_PATH="$WORKTREE"
    AD_STATE_DIR="$PROJECT_PATH/.autonomous-dev"
    STATE_FILE="$AD_STATE_DIR/state.json"
    LOG_FILE="$AD_STATE_DIR/pipeline-runner.log"
  elif [ -n "$WORKTREE" ] && [ ! -d "$WORKTREE" ]; then
    # Worktree path in state but dir doesn't exist — check for worktree created by Tashmia
    # Common pattern: skystream-dev-91, skystream-feat-xxx
    PARENT_DIR="$(dirname "$PROJECT_PATH")"
    REPO_NAME="$(basename "$PROJECT_PATH")"
    for candidate in "$PARENT_DIR/${REPO_NAME}-"*; do
      if [ -d "$candidate/.autonomous-dev" ]; then
        log "Found worktree candidate: $candidate — switching"
        PROJECT_PATH="$candidate"
        AD_STATE_DIR="$PROJECT_PATH/.autonomous-dev"
        STATE_FILE="$AD_STATE_DIR/state.json"
        LOG_FILE="$AD_STATE_DIR/pipeline-runner.log"
        break
      fi
    done
  fi

  RESUME_OUT="$(run_orchestrate resume)"
  log_json "resume" "$RESUME_OUT"

  VERIFY_OUT="$(run_orchestrate verify-state)"
  log_json "verify-state" "$VERIFY_OUT"

  verify_status="$(echo "$VERIFY_OUT" | jq -r '.status // "unknown"' 2>/dev/null)"
  if [ "$verify_status" = "warning" ]; then
    warnings="$(echo "$VERIFY_OUT" | jq -r '.warnings // ""' 2>/dev/null)"
    log "WARNING: State verification issues: $warnings"
    notify "Pipeline resumed with warnings: $warnings"
  else
    notify "Pipeline resumed successfully"
  fi
else
  log "No state file — initializing pipeline"
  INIT_OUT="$(run_orchestrate init "$PROJECT_PATH")"
  log_json "init" "$INIT_OUT"
  notify "Pipeline initialized for $PROJECT_PATH"
fi

# ─── Main loop ───

CONSECUTIVE_ERRORS=0
MAX_CONSECUTIVE_ERRORS=5
ITERATION=0
MAX_ITERATIONS=500

while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
  ITERATION=$((ITERATION + 1))

  # Get next action from orchestrator
  NEXT_OUT="$(run_orchestrate next)" || true
  log_json "next[$ITERATION]" "$NEXT_OUT"

  # Parse action
  ACTION="$(echo "$NEXT_OUT" | jq -r '.action // "error"' 2>/dev/null)"
  if [ -z "$ACTION" ] || [ "$ACTION" = "null" ]; then
    ACTION="error"
  fi

  STEP="$(echo "$NEXT_OUT" | jq -r '.step // "unknown"' 2>/dev/null)"
  MESSAGE="$(echo "$NEXT_OUT" | jq -r '.message // ""' 2>/dev/null)"

  log "Action: $ACTION | Step: $STEP | Iteration: $ITERATION"

  case "$ACTION" in

    # ── spawn: launch a Claude Code agent ──
    spawn)
      CONSECUTIVE_ERRORS=0
      TEMPLATE="$(echo "$NEXT_OUT" | jq -r '.template // ""' 2>/dev/null)"
      MODEL_ROLE="$(echo "$NEXT_OUT" | jq -r '.model // "coder"' 2>/dev/null)"
      TIMEOUT="$(echo "$NEXT_OUT" | jq -r '.timeout // 3600' 2>/dev/null)"
      STORY_ID="$(echo "$NEXT_OUT" | jq -r '.story // ""' 2>/dev/null)"

      RESOLVED_MODEL="$(resolve_model "$MODEL_ROLE")"
      log "Spawning: step=$STEP model=$RESOLVED_MODEL role=$MODEL_ROLE timeout=${TIMEOUT}s"
      notify "Spawning $STEP ($MODEL_ROLE as $RESOLVED_MODEL)"

      if [ "$STEP" = "story-execute" ] && [ -n "$STORY_ID" ]; then
        # Use spawn-coder.sh for story execution
        SPAWN_LOG="$AD_STATE_DIR/spawn-${STORY_ID}.log"
        log "Story execute: $STORY_ID via spawn-coder.sh"

        "$SPAWN_CODER" "$STORY_ID" "$PROJECT_PATH" "$RESOLVED_MODEL" > "$SPAWN_LOG" 2>&1 &
        SPAWN_PID=$!
        SPAWNED_PIDS+=("$SPAWN_PID")

        wait_with_timeout "$SPAWN_PID" "$TIMEOUT"
        SPAWN_EXIT=$?

        # Check spawn log for status
        SPAWN_STATUS="unknown"
        if [ -f "$SPAWN_LOG" ]; then
          if grep -q "status: complete" "$SPAWN_LOG" 2>/dev/null; then
            SPAWN_STATUS="complete"
          elif grep -q "status: blocked" "$SPAWN_LOG" 2>/dev/null; then
            SPAWN_STATUS="blocked"
          fi
        fi

        if [ "$SPAWN_EXIT" -eq 124 ]; then
          log "Story $STORY_ID timed out after ${TIMEOUT}s"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Timed out after ${TIMEOUT}s")"
          log_json "complete-timeout" "$COMPLETE_OUT"
          notify "Story $STORY_ID timed out"
        elif [ "$SPAWN_STATUS" = "complete" ]; then
          log "Story $STORY_ID completed"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP")"
          log_json "complete-story" "$COMPLETE_OUT"
          notify "Story $STORY_ID completed"
        elif [ "$SPAWN_STATUS" = "blocked" ]; then
          BLOCK_REASON="$(grep "status: blocked" "$SPAWN_LOG" 2>/dev/null | head -1)"
          log "Story $STORY_ID blocked: $BLOCK_REASON"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "$BLOCK_REASON")"
          log_json "complete-blocked" "$COMPLETE_OUT"
          notify "Story $STORY_ID blocked: $BLOCK_REASON"
        else
          log "Story $STORY_ID finished with status=$SPAWN_STATUS exit=$SPAWN_EXIT"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP")"
          log_json "complete-unknown" "$COMPLETE_OUT"
        fi
      else
        # Generic spawn: research, planner, reviewer, grill, final-review, simplify, etc.
        PROMPT_CONTENT="$(resolve_template "$TEMPLATE")"
        if [ -z "$PROMPT_CONTENT" ]; then
          log "ERROR: Empty template for $STEP ($TEMPLATE)"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Template $TEMPLATE not found or empty")"
          log_json "complete-no-template" "$COMPLETE_OUT"
          continue
        fi

        SPAWN_LOG="$AD_STATE_DIR/spawn-${STEP}.log"
        log "Generic spawn: $STEP via $AD_LLM_CLI --model $RESOLVED_MODEL"

        cd "$PROJECT_PATH" || { log "ERROR: Cannot cd to $PROJECT_PATH"; exit 1; }
        "$AD_LLM_CLI" --model "$RESOLVED_MODEL" --permission-mode bypassPermissions --print "$PROMPT_CONTENT" > "$SPAWN_LOG" 2>&1 &
        SPAWN_PID=$!
        SPAWNED_PIDS+=("$SPAWN_PID")

        wait_with_timeout "$SPAWN_PID" "$TIMEOUT"
        SPAWN_EXIT=$?

        if [ "$SPAWN_EXIT" -eq 124 ]; then
          log "Step $STEP timed out after ${TIMEOUT}s"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Timed out after ${TIMEOUT}s")"
          log_json "complete-timeout" "$COMPLETE_OUT"
          notify "Step $STEP timed out"
        else
          # Check for blocked markers in output
          if grep -qE "BLOCKED|STORY_BLOCKED|REVIEW_BLOCKED" "$SPAWN_LOG" 2>/dev/null; then
            BLOCK_LINE="$(grep -E "BLOCKED|STORY_BLOCKED|REVIEW_BLOCKED" "$SPAWN_LOG" 2>/dev/null | head -1)"
            log "Step $STEP reported blocked: $BLOCK_LINE"
            COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "$BLOCK_LINE")"
            log_json "complete-blocked" "$COMPLETE_OUT"
            notify "Step $STEP blocked: $BLOCK_LINE"
          else
            log "Step $STEP completed (exit=$SPAWN_EXIT)"
            COMPLETE_OUT="$(run_orchestrate complete "$STEP")"
            log_json "complete" "$COMPLETE_OUT"
            notify "Step $STEP completed"
          fi
        fi
      fi
      ;;

    # ── run: execute commands from worktree ──
    run)
      CONSECUTIVE_ERRORS=0
      log "Run action for step: $STEP"

      COMMANDS="$(echo "$NEXT_OUT" | jq -r '.commands[]? // empty' 2>/dev/null)"
      RUN_EXIT=0

      cd "$PROJECT_PATH" || { log "ERROR: Cannot cd to $PROJECT_PATH"; exit 1; }

      if [ -n "$COMMANDS" ]; then
        while IFS= read -r cmd; do
          log "Executing: $cmd"
          if ! eval "$cmd" >> "$LOG_FILE" 2>&1; then
            log "Command failed: $cmd"
            RUN_EXIT=1
            break
          fi
        done <<< "$COMMANDS"
      fi

      if [ "$RUN_EXIT" -eq 0 ]; then
        COMPLETE_OUT="$(run_orchestrate complete "$STEP")"
        log_json "complete-run" "$COMPLETE_OUT"
      elif [ "$STEP" = "story-verify" ]; then
        # Quality gate failed — spawn Claude Code to fix the issues, then retry
        log "Quality gate failed for $STEP. Spawning Claude Code to fix issues..."
        FIX_MODEL="$(resolve_model coder)"
        FIX_WORKTREE="$(jq -r '.project.worktree // .project.path // "."' "$STATE_FILE")"
        FIX_PROMPT="The quality gate failed with lint/analysis issues. Fix ALL issues reported by: $PIPELINE_DIR/scripts/quality-gate.sh --scope story

Run the gate first to see the issues, fix every one, run flutter test to verify nothing broke, then commit with message 'fix: resolve quality gate issues' and trailer Co-Authored-By: $CO_AUTHOR. NEVER add AI/Claude co-author lines."

        cd "$FIX_WORKTREE" || true
        log "Fix spawn: claude --model $FIX_MODEL (timeout: 600s)"
        timeout 600 claude --model "$FIX_MODEL" --permission-mode bypassPermissions --print "$FIX_PROMPT" \
          >> "$LOG_FILE" 2>&1
        FIX_EXIT=$?

        if [ $FIX_EXIT -eq 0 ]; then
          log "Fix completed (exit 0). Re-running quality gate..."
          cd "$PROJECT_PATH" || true
          RETRY_EXIT=0
          while IFS= read -r cmd; do
            if ! eval "$cmd" >> "$LOG_FILE" 2>&1; then
              RETRY_EXIT=1
              break
            fi
          done <<< "$COMMANDS"

          if [ $RETRY_EXIT -eq 0 ]; then
            log "Quality gate passed after fix."
            COMPLETE_OUT="$(run_orchestrate complete "$STEP")"
            log_json "complete-run-fixed" "$COMPLETE_OUT"
          else
            log "Quality gate still failing after fix."
            COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Quality gate failed after fix attempt")"
            log_json "complete-run-fix-failed" "$COMPLETE_OUT"
          fi
        else
          log "Fix spawn failed (exit $FIX_EXIT)."
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Quality gate fix failed (exit $FIX_EXIT)")"
          log_json "complete-run-fix-failed" "$COMPLETE_OUT"
        fi
      else
        COMPLETE_OUT="$(run_orchestrate complete "$STEP" "blocked" "Command execution failed")"
        log_json "complete-run-failed" "$COMPLETE_OUT"
      fi
      ;;

    # ── ask/gate: handle prompts ──
    ask|gate)
      CONSECUTIVE_ERRORS=0

      # Extract verification token for auto-answers
      ASK_TOKEN="$(echo "$NEXT_OUT" | jq -r '.verificationToken // ""' 2>/dev/null)"

      # Auto-answer known prompts
      # Format: complete <step> <token>:success <data>
      # The token goes in arg2 (STATUS), the actual value goes in arg3 (DATA)
      case "$STEP" in
        tool-select)
          log "Auto-answering tool-select: claude"
          if [ -n "$ASK_TOKEN" ]; then
            COMPLETE_OUT="$(run_orchestrate complete tool-select "${ASK_TOKEN}:success" "claude")"
          else
            COMPLETE_OUT="$(run_orchestrate complete tool-select success claude)"
          fi
          log_json "complete-tool-select" "$COMPLETE_OUT"
          ;;
        mode-select)
          log "Auto-answering mode-select: $MODE"
          if [ -n "$ASK_TOKEN" ]; then
            COMPLETE_OUT="$(run_orchestrate complete mode-select "${ASK_TOKEN}:success" "$MODE")"
          else
            COMPLETE_OUT="$(run_orchestrate complete mode-select success "$MODE")"
          fi
          log_json "complete-mode-select" "$COMPLETE_OUT"
          ;;
        preset-select)
          log "Auto-answering preset-select: $PRESET"
          if [ -n "$ASK_TOKEN" ]; then
            COMPLETE_OUT="$(run_orchestrate complete preset-select "${ASK_TOKEN}:success" "$PRESET")"
          else
            COMPLETE_OUT="$(run_orchestrate complete preset-select success "$PRESET")"
          fi
          log_json "complete-preset-select" "$COMPLETE_OUT"
          ;;
        research-review|plan-review|phase-gate)
          TOKEN="$(echo "$NEXT_OUT" | jq -r '.verificationToken // ""' 2>/dev/null)"
          GATE_DATA="$(echo "$NEXT_OUT" | jq -c '.data // {}' 2>/dev/null)"

          if [ "$MODE" = "autonomous" ]; then
            # Autonomous: auto-proceed, just log and notify
            log "Gate $STEP: auto-proceeding (autonomous mode)"
            notify "Pipeline gate $STEP: auto-approved (autonomous mode). Summary: $GATE_DATA"
            COMPLETE_OUT="$(run_orchestrate complete "$STEP" "${TOKEN}:success" "proceed")"
            log_json "complete-gate-auto" "$COMPLETE_OUT"
          else
            # Supervised: write pending file and exit for human review
            log "Gate reached: $STEP — writing pending-gate.json and exiting"

            cat > "$AD_STATE_DIR/pending-gate.json" << GATEJSON
{
  "step": "$STEP",
  "token": "$TOKEN",
  "data": $GATE_DATA,
  "message": "$MESSAGE",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
GATEJSON

            notify "Pipeline gate: $STEP requires human review. See pending-gate.json"
            log "Exit 2: gate pending at $STEP"
            exit 2
          fi
          ;;
        *)
          log "Unknown ask/gate step: $STEP — auto-completing"
          COMPLETE_OUT="$(run_orchestrate complete "$STEP" success)"
          log_json "complete-auto" "$COMPLETE_OUT"
          ;;
      esac
      ;;

    # ── progress: log and continue ──
    progress)
      CONSECUTIVE_ERRORS=0
      log "Progress: $MESSAGE"
      # Continue to next iteration — orchestrate will emit the real action
      ;;

    # ── blocked: fatal — notify and exit ──
    blocked)
      REASON="$(echo "$NEXT_OUT" | jq -r '.reason // "unknown"' 2>/dev/null)"
      log "BLOCKED: $REASON"
      notify "Pipeline BLOCKED: $REASON"
      exit 1
      ;;

    # ── complete: pipeline finished ──
    complete)
      PR_URL="$(echo "$NEXT_OUT" | jq -r '.prUrl // "none"' 2>/dev/null)"
      STORIES="$(echo "$NEXT_OUT" | jq -r '.stories // "?"' 2>/dev/null)"
      PHASES="$(echo "$NEXT_OUT" | jq -r '.phases // "?"' 2>/dev/null)"

      log "Pipeline COMPLETE: PR=$PR_URL stories=$STORIES phases=$PHASES"
      notify "Pipeline complete! PR: $PR_URL ($STORIES stories, $PHASES phases)"
      exit 0
      ;;

    # ── preflight: auto-complete ──
    preflight)
      CONSECUTIVE_ERRORS=0
      log "Preflight: auto-completing"
      COMPLETE_OUT="$(run_orchestrate complete preflight)"
      log_json "complete-preflight" "$COMPLETE_OUT"
      ;;

    # ── error: track consecutive errors ──
    error)
      CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
      log "ERROR ($CONSECUTIVE_ERRORS/$MAX_CONSECUTIVE_ERRORS): $MESSAGE"

      if [ "$CONSECUTIVE_ERRORS" -ge "$MAX_CONSECUTIVE_ERRORS" ]; then
        log "FATAL: $MAX_CONSECUTIVE_ERRORS consecutive errors — aborting pipeline"
        notify "Pipeline ABORTED: $MAX_CONSECUTIVE_ERRORS consecutive errors. Last: $MESSAGE"
        exit 1
      fi
      ;;

    # ── info/resume/verify-state: informational, continue ──
    info|resume|verify-state)
      log "Info: $MESSAGE"
      ;;

    # ── stopped: pipeline was stopped ──
    stopped)
      log "Pipeline stopped: $MESSAGE"
      notify "Pipeline stopped: $MESSAGE"
      exit 0
      ;;

    # ── unknown action ──
    *)
      CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
      log "Unknown action: $ACTION ($CONSECUTIVE_ERRORS/$MAX_CONSECUTIVE_ERRORS)"
      if [ "$CONSECUTIVE_ERRORS" -ge "$MAX_CONSECUTIVE_ERRORS" ]; then
        log "FATAL: Too many unknown actions — aborting"
        notify "Pipeline ABORTED: repeated unknown actions"
        exit 1
      fi
      ;;
  esac
done

log "FATAL: Exceeded max iterations ($MAX_ITERATIONS)"
notify "Pipeline ABORTED: exceeded $MAX_ITERATIONS iterations"
exit 1
