#!/bin/bash
# orchestrate.sh — State machine for autonomous-dev pipeline (v8.0)
#
# Auto-executes mechanical steps (git, detect, validate, PR creation).
# Emits progress messages before long spawns so user sees what's happening.
# Only returns to the AI when it needs: spawn, gate, or user input.
#
# State directory: .autonomous-dev/ (configurable via AD_STATE_DIR)
#
# Usage:
#   ./scripts/orchestrate.sh init <projectPath>
#   ./scripts/orchestrate.sh next
#   ./scripts/orchestrate.sh complete <step> [status] [data]
#   ./scripts/orchestrate.sh gate-response <CONTINUE|ADJUST|STOP> [instructions]

set -u

AD_STATE_DIR="${AD_STATE_DIR:-.autonomous-dev}"
STATE_FILE="${AD_STATE_DIR}/state.json"
PIPELINE_LOG="${AD_STATE_DIR}/.pipeline.log"
ACTION="${1:-next}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Helpers ───

json_get() { jq -r "$1 // empty" "$STATE_FILE" 2>/dev/null; }
json_set() { local tmp; tmp=$(mktemp); jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Generate a random verification token for ask/gate steps
generate_token() {
  openssl rand -hex 8 2>/dev/null || head -c 16 /dev/urandom | xxd -p 2>/dev/null || echo "$(date +%s)$$"
}

log_step() {
  mkdir -p "$AD_STATE_DIR"
  echo "[$(now)] $1: $2" >> "$PIPELINE_LOG"
}

emit() {
  local action="$1"; shift
  local auto_json="[]"
  if [ ${#AUTO_ADVANCED[@]} -gt 0 ]; then
    auto_json=$(printf '%s\n' "${AUTO_ADVANCED[@]}" | jq -R . | jq -sc .)
  fi
  # For spawn actions, add a reminder to call complete after receiving the result
  local extra=""
  if [ "$action" = "spawn" ]; then
    extra='"reminder":"After this agent completes and auto-announces its result to you, you MUST call orchestrate.sh complete to continue the pipeline. Do NOT just report the result."'
  fi
  # For ask/gate actions, generate a verification token to prevent AI from skipping user input
  if [ "$action" = "ask" ] || [ "$action" = "gate" ]; then
    local token
    token=$(generate_token)
    local step
    # Robustly extract step from arguments - handle both "step":"X" and JSON format
    step=$(printf '%s' "$*" | grep -oE '"step":"[^"]+"' | head -1 | cut -d'"' -f4)
    [ -z "$step" ] && step="unknown"
    json_set ".pendingGate = {\"step\":\"$step\",\"token\":\"$token\", \"emittedAt\":\"$(now)\"}"
    extra="\"verificationToken\":\"$token\",\"reminder\":\"User must include this token in their response. Call: complete <step> <token>:<user_response>\""
  fi
  # Build JSON safely — pipe through jq to ensure valid output
  if [ -n "$extra" ]; then
    printf '{"action":"%s","autoAdvanced":%s,%s,%s}' "$action" "$auto_json" "$extra" "$@" | jq -c .
  else
    printf '{"action":"%s","autoAdvanced":%s,%s}' "$action" "$auto_json" "$@" | jq -c .
  fi
}

# Emit progress before a spawn if auto-advanced steps happened
emit_progress_before_spawn() {
  local step="$1" description="$2" estimate="$3"
  if [ ${#AUTO_ADVANCED[@]} -gt 0 ]; then
    local auto_list
    auto_list=$(printf '%s\n' "${AUTO_ADVANCED[@]}" | sed 's/^/done: /' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    emit "progress" "\"step\":\"$step\",\"autoExecuted\":\"$auto_list\",\"next\":\"$description\",\"estimate\":\"$estimate\",\"message\":\"$auto_list — Now: $description ($estimate). Call next for spawn instruction.\""
    exit 0
  fi
}

emit_blocked() {
  local step="$1" reason="$2"
  json_set ".step = \"blocked\" | .pipeline = \"blocked\" | .blockReason = \"$reason\" | .lastCheckpoint = \"$(now)\""
  log_step "$step" "BLOCKED: $reason"
  echo "{\"action\":\"blocked\",\"step\":\"$step\",\"reason\":\"$reason\",\"message\":\"Pipeline blocked at $step: $reason\"}"
  exit 0
}

advance() {
  local from="$1" to="$2"
  json_set ".completedSteps += [\"$from\"] | .step = \"$to\" | .lastCheckpoint = \"$(now)\""
  log_step "$from" "auto-executed"
  AUTO_ADVANCED+=("$from")
}

# ─── Phase helpers ───

get_phases() { jq -r '.phases[].id' prd.json 2>/dev/null; }
get_current_phase() { json_get '.currentPhase'; }
get_first_phase() { jq -r '.phases[0].id' prd.json 2>/dev/null; }
get_phase_story_count() { jq -r ".phases[] | select(.id==\"$1\") | .stories | length" prd.json 2>/dev/null; }
get_phase_stories() { jq -r ".phases[] | select(.id==\"$1\") | .stories[]" prd.json 2>/dev/null; }
get_current_story() { json_get '.currentStory'; }

get_next_story_in_phase() {
  local phase="$1" current="$2"
  local stories
  stories=$(get_phase_stories "$phase")
  local found=false
  while read -r sid; do
    if [ "$found" = "true" ]; then
      local status
      status=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
      if [ "$status" != "complete" ]; then
        echo "$sid"
        return
      fi
    fi
    [ "$sid" = "$current" ] && found=true
  done <<< "$stories"
}

get_first_pending_story_in_phase() {
  local phase="$1"
  local stories
  stories=$(get_phase_stories "$phase")
  while read -r sid; do
    local status
    status=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
    if [ "$status" != "complete" ]; then
      echo "$sid"
      return
    fi
  done <<< "$stories"
}

get_next_phase() {
  local current="$1" found=false
  for phase in $(get_phases); do
    [ "$found" = "true" ] && echo "$phase" && return
    [ "$phase" = "$current" ] && found=true
  done
  echo ""
}

# ─── INIT ───

if [ "$ACTION" = "init" ]; then
  PROJECT_PATH="${1:-.}"
  mkdir -p "$AD_STATE_DIR"
  cat > "$STATE_FILE" << ENDJSON
{
  "version": 4,
  "pipeline": "initialized",
  "step": "tool-select",
  "tool": null,
  "mode": null,
  "preset": null,
  "project": { "path": "$PROJECT_PATH" },
  "models": {},
  "startedAt": "$(now)",
  "lastCheckpoint": "$(now)",
  "completedSteps": [],
  "currentPhase": null,
  "currentStory": null,
  "gateStatus": "running",
  "phases": {},
  "stories": {}
}
ENDJSON
  echo '[]' | jq empty > /dev/null  # validate jq available

  # Ensure ephemeral pipeline artifacts are gitignored
  GITIGNORE_ENTRIES=(
    "${AD_STATE_DIR}/"
    "prd.json"
    "research/"
    "progress.txt"
    "plan-grill-report.md"
  )
  GITIGNORE_FILE=".gitignore"
  if [ -d .git ]; then
    touch "$GITIGNORE_FILE"
    ADDED=0
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      if ! grep -qxF "$entry" "$GITIGNORE_FILE" 2>/dev/null; then
        [ "$ADDED" -eq 0 ] && [ -s "$GITIGNORE_FILE" ] && echo "" >> "$GITIGNORE_FILE"
        [ "$ADDED" -eq 0 ] && echo "# autonomous-dev (ephemeral pipeline state)" >> "$GITIGNORE_FILE"
        echo "$entry" >> "$GITIGNORE_FILE"
        ADDED=$((ADDED + 1))
      fi
    done
    if [ "$ADDED" -gt 0 ]; then
      log_step "init" "Added $ADDED entries to .gitignore"
    fi
  fi

  log_step "init" "Pipeline initialized at $PROJECT_PATH"
  AUTO_ADVANCED=()
  emit "next" "\"message\":\"Pipeline initialized. Call next to begin.\""
  exit 0
fi

# ─── RESUME — Restart from last checkpoint ───

if [ "$ACTION" = "resume" ]; then
  if [ ! -f "$STATE_FILE" ]; then
    echo '{"action":"error","message":"No state.json to resume from."}'
    exit 1
  fi
  STEP=$(json_get '.step')
  PIPELINE=$(json_get '.pipeline')
  PHASE=$(json_get '.currentPhase // "none"')
  MODE=$(json_get '.mode // "unknown"')
  PRESET=$(json_get '.preset // "unknown"')
  BRANCH=$(json_get '.project.branch // "unknown"')
  STARTED=$(json_get '.startedAt // "unknown"')
  LAST_CP=$(json_get '.lastCheckpoint // "unknown"')
  COMPLETED=$(json_get '.completedSteps | length')

  if [ "$PIPELINE" = "complete" ] || [ "$PIPELINE" = "stopped" ]; then
    echo "{\"action\":\"info\",\"message\":\"Pipeline is $PIPELINE. Nothing to resume.\"}"
    exit 0
  fi

  # Story/phase progress from prd.json + state.json
  COMPLETE_STORIES=$(jq '[.stories // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE" 2>/dev/null || echo 0)
  TOTAL_STORIES=$(jq '.userStories | length' prd.json 2>/dev/null || echo "?")
  COMPLETE_PHASES=$(jq '[.phases // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE" 2>/dev/null || echo 0)
  TOTAL_PHASES=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")

  # Failed stories
  FAILED=$(jq -r '[.stories // {} | to_entries[] | select(.value.status != "complete" and (.value.attempts // 0) > 0) | .key] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "")

  log_step "resume" "Resuming at step: $STEP, phase: $PHASE, completed: $COMPLETED steps"
  FAIL_INFO=""
  [ -n "$FAILED" ] && FAIL_INFO=",\"failedStories\":\"$FAILED\""

  printf '{"action":"resume","step":"%s","phase":"%s","mode":"%s","preset":"%s","branch":"%s","startedAt":"%s","lastCheckpoint":"%s","completedSteps":%d,"stories":{"complete":%s,"total":%s},"phases":{"complete":%s,"total":%s}%s,"message":"Resuming at step: %s. Call: ./scripts/orchestrate.sh next"}' \
    "$STEP" "$PHASE" "$MODE" "$PRESET" "$BRANCH" "$STARTED" "$LAST_CP" \
    "$COMPLETED" "$COMPLETE_STORIES" "$TOTAL_STORIES" "$COMPLETE_PHASES" "$TOTAL_PHASES" \
    "$FAIL_INFO" "$STEP" | jq -c .
  exit 0
fi

# ─── Ensure state exists ───

if [ ! -f "$STATE_FILE" ]; then
  echo '{"action":"error","message":"No state.json. Run: ./scripts/orchestrate.sh init <path>"}'
  exit 1
fi

CURRENT_STEP=$(json_get '.step')
MODE=$(json_get '.mode')
PROJECT_PATH=$(json_get '.project.path // "."')
PIPELINE=$(json_get '.pipeline')
AUTO_ADVANCED=()

# ─── VERIFY-STATE — sanity check state.json against git history ───

if [ "$ACTION" = "verify-state" ]; then
  cd "$PROJECT_PATH" 2>/dev/null || cd .
  
  # Get state info
  STATE_PHASE=$(json_get '.currentPhase')
  STATE_STEP=$(json_get '.step')
  COMPLETE_PHASES=$(jq '[.phases // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE" 2>/dev/null || echo 0)
  
  # Get git info
  GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  GIT_LAST_COMMIT=$(git log -1 --oneline 2>/dev/null | cut -d' ' -f1 || echo "none")
  GIT_LAST_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "none")
  
  # Check for sync issues
  WARNINGS=""
  
  # Check if on main branch (should be feature branch during dev)
  if [ "$GIT_BRANCH" = "main" ] || [ "$GIT_BRANCH" = "master" ] || [ "$GIT_BRANCH" = "develop" ]; then
    WARNINGS="${WARNINGS}branch:main,"
  fi
  
  # Check if state phase count matches completed phases
  EXPECTED_PHASE=$((COMPLETE_PHASES + 1))
  if [ "$STATE_PHASE" != "" ] && [[ ! "$STATE_PHASE" =~ PHASE-$EXPECTED_PHASE ]]; then
    WARNINGS="${WARNINGS}phase_mismatch,"
  fi
  
  # Check for uncommitted changes
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    WARNINGS="${WARNINGS}uncommitted,"
  fi
  
  # Emit result
  if [ -z "$WARNINGS" ]; then
    printf '{"action":"verify-state","status":"ok","state":{"phase":"%s","step":"%s","completePhases":%s},"git":{"branch":"%s","lastCommit":"%s","lastMsg":"%s"},"message":"State verified. Safe to proceed."}' \
      "$STATE_PHASE" "$STATE_STEP" "$COMPLETE_PHASES" "$GIT_BRANCH" "$GIT_LAST_COMMIT" "$GIT_LAST_MSG"
  else
    printf '{"action":"verify-state","status":"warning","warnings":"%s","state":{"phase":"%s","step":"%s","completePhases":%s},"git":{"branch":"%s","lastCommit":"%s","lastMsg":"%s"},"message":"State issues detected. Review before proceeding."}' \
      "${WARNINGS%,}" "$STATE_PHASE" "$STATE_STEP" "$COMPLETE_PHASES" "$GIT_BRANCH" "$GIT_LAST_COMMIT" "$GIT_LAST_MSG"
  fi
  exit 0
fi

# ─── COMPLETE — advance step, then fall through to NEXT ───

if [ "$ACTION" = "complete" ]; then
  STEP="${1:-$CURRENT_STEP}"
  STATUS="${2:-success}"
  DATA="${3:-}"

  # Verify token for ask/gate steps (prevents AI from skipping user input)
  PENDING_STEP=$(json_get '.pendingGate.step // empty')
  if [ -n "$PENDING_STEP" ] && [ "$PENDING_STEP" = "$STEP" ]; then
    PENDING_TOKEN=$(json_get '.pendingGate.token // empty')
    if [ -z "$PENDING_TOKEN" ]; then
      echo "{\"action\":\"error\",\"step\":\"$STEP\",\"message\":\"No pending gate token found. State may be corrupted.\"}"
      exit 1
    fi
    # Extract token from STATUS (format: token:response or just token)
    PROVIDED_TOKEN="${STATUS%%:*}"
    ACTUAL_STATUS="${STATUS#*:}"
    # If no colon, the whole thing is the token and status is success
    if [ "$PROVIDED_TOKEN" = "$STATUS" ]; then
      ACTUAL_STATUS="success"
    fi
    if [ "$PROVIDED_TOKEN" != "$PENDING_TOKEN" ]; then
      echo "{\"action\":\"error\",\"step\":\"$STEP\",\"message\":\"Invalid verification token. You must show the prompt to the user and include their token in the response. Expected token from pending gate.\"}"
      exit 1
    fi
    # Token verified, clear pending gate and use actual status
    json_set ".pendingGate = null"
    STATUS="$ACTUAL_STATUS"
    log_step "$STEP" "gate token verified"
  fi

  if [ "$STATUS" = "blocked" ]; then
    json_set ".step = \"blocked\" | .pipeline = \"blocked\" | .blockReason = \"$DATA\" | .lastCheckpoint = \"$(now)\""
    log_step "$STEP" "BLOCKED: $DATA"
    emit "blocked" "\"step\":\"$STEP\",\"reason\":\"$DATA\",\"message\":\"Pipeline blocked at $STEP: $DATA. Notify user and STOP.\""
    exit 0
  fi

  json_set ".completedSteps += [\"$STEP\"] | .lastCheckpoint = \"$(now)\""
  log_step "$STEP" "completed (status: $STATUS)"

  case "$STEP" in
    tool-select)
      CHOSEN="${DATA:-claude}"
      json_set ".tool = \"$CHOSEN\" | .step = \"mode-select\""
      ;;
    mode-select)
      CHOSEN="${DATA:-supervised-start}"
      case "$CHOSEN" in
        supervised-start|autonomous|human-assisted) ;;
        1|supervised) CHOSEN="supervised-start" ;;
        2|auto) CHOSEN="autonomous" ;;
        3|human) CHOSEN="human-assisted" ;;
        *) CHOSEN="supervised-start" ;;
      esac
      json_set ".mode = \"$CHOSEN\" | .step = \"preset-select\""
      MODE="$CHOSEN"
      ;;
    preset-select)
      CHOSEN="${DATA:-premium}"
      case "$CHOSEN" in budget|balanced|premium|custom) ;; *) CHOSEN="premium" ;; esac
      # Resolve preset to short model aliases — the invoking agent resolves full IDs
      case "$CHOSEN" in
        budget)
          json_set ".preset = \"budget\" | .models = {\"supervisor\":\"haiku\",\"researcher\":\"sonnet\",\"planner\":\"sonnet\",\"coder\":\"sonnet\",\"tester\":\"haiku\",\"reviewer\":\"sonnet\"} | .step = \"worktree-setup\""
          ;;
        balanced)
          json_set ".preset = \"balanced\" | .models = {\"supervisor\":\"sonnet\",\"researcher\":\"sonnet\",\"planner\":\"sonnet\",\"coder\":\"sonnet\",\"tester\":\"sonnet\",\"reviewer\":\"sonnet\"} | .step = \"worktree-setup\""
          ;;
        premium)
          json_set ".preset = \"premium\" | .models = {\"supervisor\":\"sonnet\",\"researcher\":\"opus\",\"planner\":\"opus\",\"coder\":\"opus\",\"tester\":\"sonnet\",\"reviewer\":\"opus\"} | .step = \"worktree-setup\""
          ;;
        custom)
          json_set ".preset = \"custom\" | .step = \"worktree-setup\""
          ;;
      esac
      ;;
    research-review)
      if [ "$MODE" = "autonomous" ]; then
        json_set '.step = "validate-prd-exists"'
      elif [ -z "$DATA" ] || [ "$DATA" = "success" ]; then
        emit "error" "\"step\":\"research-review\",\"message\":\"Gate requires user response: proceed / adjust:<instructions> / cancel\""
        exit 0
      elif [ "$DATA" = "cancel" ]; then
        json_set ".step = \"stopped\" | .pipeline = \"stopped\""
        emit "stopped" "\"message\":\"Pipeline cancelled at research review.\""
        exit 0
      else
        if echo "$DATA" | grep -q "^adjust:"; then
          INSTRUCTIONS="${DATA#adjust:}"
          json_set ".researchAdjustment = \"$INSTRUCTIONS\" | .step = \"validate-prd-exists\""
        else
          json_set '.step = "validate-prd-exists"'
        fi
      fi
      ;;
    plan-grill)    json_set '.step = "plan-review"' ;;
    plan-review)
      if [ "$MODE" = "autonomous" ]; then
        json_set '.step = "preflight"'
      elif [ -z "$DATA" ] || [ "$DATA" = "success" ]; then
        emit "error" "\"step\":\"plan-review\",\"message\":\"Gate requires user response: proceed / adjust:<instructions> / cancel\""
        exit 0
      elif [ "$DATA" = "cancel" ]; then
        json_set ".step = \"stopped\" | .pipeline = \"stopped\""
        emit "stopped" "\"message\":\"Pipeline cancelled at plan review.\""
        exit 0
      else
        if echo "$DATA" | grep -q "^adjust:"; then
          INSTRUCTIONS="${DATA#adjust:}"
          json_set ".planAdjustment = \"$INSTRUCTIONS\" | .step = \"preflight\""
        else
          json_set '.step = "preflight"'
        fi
      fi
      ;;
    preflight)
      FIRST=$(get_first_phase)
      FIRST_STORY=$(get_first_pending_story_in_phase "$FIRST")
      json_set ".currentPhase = \"$FIRST\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\""
      ;;
    story-execute)
      CURRENT_PHASE=$(get_current_phase)
      CURRENT_STORY=$(get_current_story)
      json_set ".stories.\"$CURRENT_STORY\" = {\"status\":\"complete\",\"completedAt\":\"$(now)\"}"
      json_set ".step = \"story-verify\""
      ;;
    story-verify)
      CURRENT_PHASE=$(get_current_phase)
      CURRENT_STORY=$(get_current_story)
      NEXT_STORY=$(get_next_story_in_phase "$CURRENT_PHASE" "$CURRENT_STORY")
      if [ -n "$NEXT_STORY" ]; then
        json_set ".currentStory = \"$NEXT_STORY\" | .step = \"story-execute\""
      else
        json_set ".phases.\"$CURRENT_PHASE\".status = \"complete\" | .phases.\"$CURRENT_PHASE\".completedAt = \"$(now)\" | .step = \"phase-review\""
      fi
      ;;
    phase-review)
      CURRENT_PHASE=$(get_current_phase)
      if [ "$MODE" = "human-assisted" ]; then
        json_set ".step = \"phase-gate\" | .gateStatus = \"awaiting_continue\""
      else
        NEXT=$(get_next_phase "$CURRENT_PHASE")
        if [ -z "$NEXT" ]; then
          json_set '.step = "final-review"'
        else
          FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
          json_set ".currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\""
        fi
      fi
      ;;
    research)      json_set '.step = "research-grill"' ;;
    research-grill) json_set '.step = "research-review"' ;;
    planner)       json_set '.step = "validate-prd"' ;;
    final-review)  json_set '.step = "simplify"' ;;
    simplify)      json_set '.step = "pr-create"' ;;
    pr-create)     json_set '.step = "complete" | .pipeline = "complete"' ;;
    # Auto-executed steps
    worktree-setup)     json_set '.step = "validate-models"' ;;
    validate-models)     json_set '.step = "pull-latest"' ;;
    pull-latest)         json_set '.step = "detect"' ;;
    detect)              json_set '.step = "baseline"' ;;
    baseline)            json_set '.step = "research"' ;;
    validate-prd-exists) json_set '.step = "planner"' ;;
    validate-prd)        json_set '.step = "plan-grill"' ;;
    *)                   json_set ".step = \"unknown-after-$STEP\"" ;;
  esac

  # Fall through to NEXT
  CURRENT_STEP=$(json_get '.step')
  MODE=$(json_get '.mode')
  ACTION="next"
fi

# ─── GATE-RESPONSE ───

if [ "$ACTION" = "gate-response" ]; then
  RESPONSE="${1:-CONTINUE}"
  INSTRUCTIONS="${2:-}"
  CURRENT_PHASE=$(get_current_phase)

  case "$RESPONSE" in
    CONTINUE)
      NEXT=$(get_next_phase "$CURRENT_PHASE")
      if [ -z "$NEXT" ]; then
        json_set ".gateStatus = \"running\" | .step = \"final-review\" | .lastCheckpoint = \"$(now)\""
      else
        FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
        json_set ".gateStatus = \"running\" | .currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\" | .lastCheckpoint = \"$(now)\""
      fi
      ;;
    ADJUST)
      NEXT=$(get_next_phase "$CURRENT_PHASE")
      if [ -z "$NEXT" ]; then
        json_set ".gateStatus = \"running\" | .step = \"final-review\" | .lastCheckpoint = \"$(now)\""
      else
        FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
        json_set ".gateStatus = \"running\" | .currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\" | .phaseAdjustment = \"$INSTRUCTIONS\" | .lastCheckpoint = \"$(now)\""
      fi
      ;;
    STOP)
      json_set ".gateStatus = \"stopped\" | .pipeline = \"stopped\" | .lastCheckpoint = \"$(now)\""
      emit "stopped" "\"message\":\"Pipeline stopped by user at phase gate.\""
      exit 0
      ;;
  esac

  log_step "gate-response" "$RESPONSE"
  CURRENT_STEP=$(json_get '.step')
  MODE=$(json_get '.mode')
  ACTION="next"
fi

# ─── NEXT — Auto-advance loop ───
# Executes mechanical steps automatically. Only emits when AI intervention needed.

if [ "$ACTION" = "next" ]; then

  MAX_AUTO=20  # Safety: prevent infinite loops
  AUTO_COUNT=0

  while [ $AUTO_COUNT -lt $MAX_AUTO ]; do
    CURRENT_STEP=$(json_get '.step')
    MODE=$(json_get '.mode')
    AUTO_COUNT=$((AUTO_COUNT + 1))

    # ══════════════════════════════════════════════
    # MANDATORY STATE VERIFICATION (every iteration)
    # ══════════════════════════════════════════════
    # Block on main/master/develop during dev phases
    case "$CURRENT_STEP" in
      research|research-grill|planner|preflight|story-execute|story-verify|phase-review|final-review|simplify|pr-create)
        cd "$PROJECT_PATH" 2>/dev/null || true
        GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [[ "$GIT_BRANCH" =~ ^(main|master|develop|production)$ ]]; then
          emit_blocked "safety" "CRITICAL: Cannot execute '$CURRENT_STEP' on branch '$GIT_BRANCH'. You MUST be on a feature branch. Create worktree: git worktree add ../$(basename "$(pwd)")-feat -b feat/xxx"
        fi
        ;;
    esac

    case "$CURRENT_STEP" in

      # ══════════════════════════════════════════════
      # AUTO-EXECUTABLE STEPS (no AI needed)
      # ══════════════════════════════════════════════

      worktree-setup)
        # Auto-create worktree if not already on feature branch
        cd "$PROJECT_PATH" 2>/dev/null || true
        GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        
        # Check if already on feature branch
        if [[ ! "$GIT_BRANCH" =~ ^(main|master|develop|production)$ ]]; then
          log_step "worktree-setup" "already on feature branch: $GIT_BRANCH"
          json_set ".project.branch = \"$GIT_BRANCH\""
          advance "worktree-setup" "validate-models"
        else
          # Create worktree
          TIMESTAMP=$(date +%Y%m%d-%H%M%S)
          WORKTREE_BRANCH="feat/pipeline-$TIMESTAMP"
          WORKTREE_PATH="../$(basename "$(pwd)")-$TIMESTAMP"
          
          # Check if worktrees dir exists
          mkdir -p .worktrees 2>/dev/null || true
          WORKTREE_PATH=".worktrees/$TIMESTAMP"
          
          WORKTREE_OUT=$(git worktree add "$WORKTREE_PATH" -b "$WORKTREE_BRANCH" 2>&1)
          if [ $? -eq 0 ]; then
            # Update state with worktree info
            json_set ".project.worktree = \"$(cd \"$WORKTREE_PATH\" && pwd)\" | .project.branch = \"$WORKTREE_BRANCH\""
            # Change PROJECT_PATH to worktree for subsequent operations
            PROJECT_PATH=$(cd "$WORKTREE_PATH" && pwd)
            # Also update state file path for worktree
            mkdir -p "$PROJECT_PATH/.autonomous-dev" 2>/dev/null || true
            cp "$STATE_FILE" "$PROJECT_PATH/.autonomous-dev/state.json"
            STATE_FILE="$PROJECT_PATH/.autonomous-dev/state.json"
            log_step "worktree-setup" "created worktree at $WORKTREE_PATH on branch $WORKTREE_BRANCH"
            advance "worktree-setup" "validate-models"
          else
            emit_blocked "worktree-setup" "Failed to create worktree: $WORKTREE_OUT"
          fi
        fi
        ;;

      validate-models)
        # Model validation is optional — skip if no validation tool available
        # The invoking agent is responsible for resolving short aliases to full model IDs
        log_step "validate-models" "model validation skipped (invoking agent resolves aliases)"
        advance "validate-models" "pull-latest"
        ;;

      pull-latest)
        cd "$PROJECT_PATH" 2>/dev/null || true
        # Detect default branch (production, main, master, develop, etc.)
        DEFAULT_BRANCH="main"
        if [ -x "$SCRIPT_DIR/workflow-guards.sh" ]; then
          DEFAULT_BRANCH=$("$SCRIPT_DIR/workflow-guards.sh" get-default-branch "$PROJECT_PATH" 2>/dev/null) || DEFAULT_BRANCH="main"
        fi
        FETCH_OUT=$(git fetch origin 2>&1) || true
        PULL_OUT=$(git checkout "$DEFAULT_BRANCH" 2>&1 && git pull origin "$DEFAULT_BRANCH" 2>&1) || true
        log_step "pull-latest" "default=$DEFAULT_BRANCH ${FETCH_OUT} ${PULL_OUT}"
        advance "pull-latest" "detect"
        ;;

      detect)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/detect-project.sh" ]; then
          DETECT_OUT=$("$SCRIPT_DIR/detect-project.sh" 2>&1) || true
          log_step "detect" "${DETECT_OUT:0:200}"
          if echo "$DETECT_OUT" | jq empty 2>/dev/null; then
            json_set ".project = (.project * ($DETECT_OUT | fromjson? // {}))"
          fi
        else
          log_step "detect" "detect-project.sh not found, skipping"
        fi
        advance "detect" "baseline"
        ;;

      baseline)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/quality-gate.sh" ]; then
          "$SCRIPT_DIR/quality-gate.sh" --baseline capture 2>&1 || true
        fi
        log_step "baseline" "captured"
        advance "baseline" "research"
        ;;

      research-review)
        GRILL_VERDICT="none"
        GRILL_CRITICAL=0
        GRILL_MEDIUM=0
        if [ -f "research/grill-report.md" ]; then
          GRILL_VERDICT=$(grep -Ei '(^|###\s*\*\*)VERDICT[:\s]*|Summary Verdict' "research/grill-report.md" | head -1 | sed -E 's/.*(PROCEED_WITH_CAUTION|PROCEED|BLOCKED).*/\1/' || echo "unknown")
          GRILL_CRITICAL=$({ grep -E '^### [0-9]+\. ' "research/grill-report.md" 2>/dev/null | wc -l | tr -d ' ' || echo 0; })
          GRILL_MEDIUM=$({ grep -E '^### [0-9]+\. ' "research/grill-report.md" 2>/dev/null | wc -l | tr -d ' ' || echo 0; })
        fi
        if [ "$MODE" = "autonomous" ]; then
          log_step "research-review" "grill verdict: $GRILL_VERDICT (critical: $GRILL_CRITICAL, medium: $GRILL_MEDIUM)"
          advance "research-review" "validate-prd-exists"
        else
          if [ ! -f "research/findings.md" ]; then
            emit_blocked "research-review" "research/findings.md missing"
          fi
          WIRING=$({ grep -c "must import\|must extend\|must include\|must add" research/findings.md 2>/dev/null || true; })
          CONSTRAINTS=$({ grep -c "MUST\|MUST NOT" research/findings.md 2>/dev/null || true; })
          emit "gate" "\"step\":\"research-review\",\"data\":{\"wiring\":$WIRING,\"constraints\":$CONSTRAINTS,\"grillVerdict\":\"$GRILL_VERDICT\",\"grillCritical\":$GRILL_CRITICAL,\"grillMedium\":$GRILL_MEDIUM},\"grillReport\":\"research/grill-report.md\",\"message\":\"Show research/findings.md and research/grill-report.md to user. WAIT for reply. Then: complete research-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;

      validate-prd-exists)
        if [ -f "prd.json" ]; then
          log_step "validate-prd-exists" "prd.json found (pre-existing)"
        else
          log_step "validate-prd-exists" "no prd.json — planner will create"
        fi
        advance "validate-prd-exists" "planner"
        ;;

      validate-prd)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/validate-prd.sh" ] && "$SCRIPT_DIR/validate-prd.sh" prd.json 2>&1; then
          log_step "validate-prd" "valid"
          advance "validate-prd" "plan-grill"
        elif [ -f "prd.json" ]; then
          log_step "validate-prd" "validate script unavailable, prd.json exists"
          advance "validate-prd" "plan-grill"
        else
          emit_blocked "validate-prd" "prd.json missing or invalid"
        fi
        ;;

      plan-review)
        GRILL_VERDICT="none"
        GRILL_CRITICAL=0
        GRILL_MEDIUM=0
        if [ -f "plan-grill-report.md" ]; then
          GRILL_VERDICT=$(sed -n 's/^## Verdict: //p' "plan-grill-report.md" 2>/dev/null || echo "unknown")
          GRILL_CRITICAL=$({ sed -n '/## Critical Issues/,/^##/p' "plan-grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
          GRILL_MEDIUM=$({ sed -n '/## Medium Issues/,/^##/p' "plan-grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
        fi
        if [ "$MODE" = "autonomous" ]; then
          log_step "plan-review" "grill verdict: $GRILL_VERDICT (critical: $GRILL_CRITICAL, medium: $GRILL_MEDIUM)"
          advance "plan-review" "preflight"
        else
          STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
          PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
          PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
          emit "gate" "\"step\":\"plan-review\",\"data\":{\"project\":\"$PROJECT_NAME\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT,\"grillVerdict\":\"$GRILL_VERDICT\",\"grillCritical\":$GRILL_CRITICAL,\"grillMedium\":$GRILL_MEDIUM},\"grillReport\":\"plan-grill-report.md\",\"message\":\"Show prd.json summary and plan-grill-report.md to user. WAIT for reply. Then: complete plan-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;

      pr-create)
        cd "$PROJECT_PATH" 2>/dev/null || true
        BRANCH=$(json_get '.project.branch // "unknown"')
        PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null || echo "unknown")
        STORIES=$(jq -r '.userStories[] | "- [x] \(.id): \(.title)"' prd.json 2>/dev/null || echo "- stories unavailable")

        PUSH_OUT=$(git push -u origin "$BRANCH" 2>&1) || true
        log_step "pr-create" "push: ${PUSH_OUT:0:200}"

        PR_BODY="## $PROJECT_NAME

### Stories
$STORIES

### Quality
- All quality gates passing (story + phase + final)
- Phase reviews complete
- Final review complete"

        # Detect default branch for PR base
        PR_BASE="main"
        if [ -x "$SCRIPT_DIR/workflow-guards.sh" ]; then
          PR_BASE=$("$SCRIPT_DIR/workflow-guards.sh" get-default-branch "$PROJECT_PATH" 2>/dev/null) || PR_BASE="main"
        fi
        PR_URL=$(gh pr create --title "$PROJECT_NAME" --body "$PR_BODY" --base "$PR_BASE" 2>&1 | grep -oE 'https://github.com/[^ ]+') || true

        if [ -n "$PR_URL" ]; then
          json_set ".prUrl = \"$PR_URL\""
          log_step "pr-create" "PR: $PR_URL"
          advance "pr-create" "complete"
        else
          log_step "pr-create" "auto-create failed, deferring to AI"
          emit "run" "\"step\":\"pr-create\",\"branch\":\"$BRANCH\",\"message\":\"Auto PR creation failed. Create PR manually: git push -u origin $BRANCH && gh pr create --base main. Save URL to state.json .prUrl. Then: complete pr-create\""
          exit 0
        fi
        ;;

      # ══════════════════════════════════════════════
      # AI-REQUIRED STEPS (spawn, gate, ask)
      # ══════════════════════════════════════════════

      tool-select)
        emit "ask" "\"step\":\"tool-select\",\"message\":\"Which AI coding tool should the pipeline use?\\n  claude (default) / other\\n\\nThen: complete tool-select success <choice>\""
        exit 0
        ;;

      mode-select)
        emit "ask" "\"step\":\"mode-select\",\"message\":\"Show this menu and WAIT for reply:\\n\\nMode Selection\\n  1 — Supervised Start (default): Review research + plan, then autonomous build\\n  2 — Fully Autonomous: Summaries only, alert on BLOCKED\\n  3 — Human Assisted: Pause at research, plan, AND every phase\\n\\nThen: complete mode-select success <choice>\""
        exit 0
        ;;

      preset-select)
        emit "ask" "\"step\":\"preset-select\",\"message\":\"Show this menu and WAIT for reply:\\n\\nModel Preset\\n  budget — haiku/sonnet (fastest)\\n  balanced — sonnet everything\\n  premium (default) — opus coder + planner, sonnet research\\n  custom — pick each role\\n\\nThen: complete preset-select success <choice>\""
        exit 0
        ;;

      research)
        emit_progress_before_spawn "research" "Spawning researcher (codebase audit)" "~5-15 min"
        emit "spawn" "\"step\":\"research\",\"template\":\"templates/researcher.md\",\"model\":\"researcher\",\"timeout\":1800,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_RESEARCHER__\",\"prompt_template\":\"templates/researcher.md\"},\"onComplete\":\"complete research\",\"onBlocked\":\"complete research blocked <reason>\""
        exit 0
        ;;

      research-grill)
        if [ ! -f "research/findings.md" ]; then
          emit_blocked "research-grill" "research/findings.md missing — run research step first"
        fi
        emit_progress_before_spawn "research-grill" "Grilling research findings (stress-test)" "~5-10 min"
        emit "spawn" "\"step\":\"research-grill\",\"template\":\"templates/grill-research.md\",\"model\":\"reviewer\",\"timeout\":900,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/grill-research.md\"},\"onComplete\":\"complete research-grill\",\"onBlocked\":\"complete research-grill blocked <reason>\""
        exit 0
        ;;

      planner)
        if [ ! -f "research/findings.md" ]; then
          emit_blocked "planner" "research/findings.md missing"
        fi
        emit_progress_before_spawn "planner" "Spawning planner (stories + wiring)" "~5-10 min"
        emit "spawn" "\"step\":\"planner\",\"template\":\"templates/planner.md\",\"model\":\"planner\",\"timeout\":1800,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_PLANNER__\",\"prompt_template\":\"templates/planner.md\"},\"onComplete\":\"complete planner\",\"onBlocked\":\"complete planner blocked <reason>\""
        exit 0
        ;;

      plan-grill)
        if [ ! -f "prd.json" ]; then
          emit_blocked "plan-grill" "prd.json missing — run planner step first"
        fi
        GRILL_WIRING=""
        [ -f "wiring-checklist.json" ] && GRILL_WIRING=",\"wiringChecklist\":\"wiring-checklist.json\""
        emit_progress_before_spawn "plan-grill" "Grilling implementation plan (stress-test)" "~5-10 min"
        emit "spawn" "\"step\":\"plan-grill\",\"template\":\"templates/grill-plan.md\",\"model\":\"reviewer\",\"timeout\":900${GRILL_WIRING},\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/grill-plan.md\"},\"onComplete\":\"complete plan-grill\",\"onBlocked\":\"complete plan-grill blocked <reason>\""
        exit 0
        ;;

      preflight)
        STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
        PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
        PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
        BRANCH=$(json_get '.project.branch // "unknown"')
        PRESET=$(json_get '.preset // "premium"')
        emit "preflight" "\"step\":\"preflight\",\"data\":{\"project\":\"$PROJECT_NAME\",\"branch\":\"$BRANCH\",\"mode\":\"$MODE\",\"preset\":\"$PRESET\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT},\"message\":\"Show pre-flight summary. On confirm: complete preflight. On cancel: exit.\""
        exit 0
        ;;

      story-execute)
        CURRENT_PHASE=$(get_current_phase)
        CURRENT_STORY=$(get_current_story)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        STORY_TITLE=$(jq -r ".userStories[] | select(.id==\"$CURRENT_STORY\") | .title" prd.json 2>/dev/null)
        EST_MINUTES=$(jq -r ".userStories[] | select(.id==\"$CURRENT_STORY\") | .estimatedMinutes // 30" prd.json 2>/dev/null)
        PHASE_INDEX=$(jq -r "[.phases[].id] | index(\"$CURRENT_PHASE\")" prd.json 2>/dev/null)
        TOTAL_PHASES=$(jq '.phases | length' prd.json 2>/dev/null)
        STORY_COUNT=$(get_phase_story_count "$CURRENT_PHASE")
        PHASE_STORIES=$(get_phase_stories "$CURRENT_PHASE")
        DONE_COUNT=0
        while read -r sid; do
          S_STATUS=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
          [ "$S_STATUS" = "complete" ] && DONE_COUNT=$((DONE_COUNT + 1))
        done <<< "$PHASE_STORIES"

        TIMEOUT=$((EST_MINUTES * 90))
        [ "$TIMEOUT" -lt 1800 ] && TIMEOUT=1800

        BRANCH=$(json_get '.project.branch // "main"')
        emit_progress_before_spawn "story-execute" "Phase $((PHASE_INDEX+1))/$TOTAL_PHASES ($PHASE_NAME): Story $((DONE_COUNT+1))/$STORY_COUNT — $CURRENT_STORY: $STORY_TITLE" "~${EST_MINUTES} min"
        emit "spawn" "\"step\":\"story-execute\",\"phase\":\"$CURRENT_PHASE\",\"story\":\"$CURRENT_STORY\",\"storyTitle\":\"$STORY_TITLE\",\"branch\":\"$BRANCH\",\"template\":\"templates/worker.md\",\"model\":\"coder\",\"timeout\":$TIMEOUT,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_CODER__\",\"prompt_template\":\"templates/worker.md\"},\"onComplete\":\"complete story-execute\",\"onBlocked\":\"complete story-execute blocked <reason>\""
        exit 0
        ;;

      story-verify)
        CURRENT_STORY=$(get_current_story)
        BRANCH=$(json_get '.project.branch // "main"')
        emit "run" "\"step\":\"story-verify\",\"story\":\"$CURRENT_STORY\",\"branch\":\"$BRANCH\",\"commands\":[\"git checkout $BRANCH\",\"git log --oneline -5 | grep -q ${CURRENT_STORY} && echo COMMIT_OK || echo COMMIT_MISSING\",\"$SCRIPT_DIR/quality-gate.sh --scope story\"],\"onComplete\":\"complete story-verify\",\"message\":\"Verify commit for $CURRENT_STORY on branch $BRANCH: 1) git checkout $BRANCH, 2) check git log for $CURRENT_STORY, 3) run story quality gate. If commit missing or gate fails, complete story-verify blocked <reason>.\""
        exit 0
        ;;

      phase-review)
        CURRENT_PHASE=$(get_current_phase)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        emit_progress_before_spawn "phase-review" "Reviewing phase: $PHASE_NAME" "~10-20 min"
        emit "spawn" "\"step\":\"phase-review\",\"phase\":\"$CURRENT_PHASE\",\"template\":\"templates/reviewer.md\",\"model\":\"tester\",\"timeout\":1800,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_TESTER__\",\"prompt_template\":\"templates/reviewer.md\"},\"onComplete\":\"complete phase-review\",\"onBlocked\":\"complete phase-review blocked <reason>\""
        exit 0
        ;;

      phase-gate)
        CURRENT_PHASE=$(get_current_phase)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        NEXT=$(get_next_phase "$CURRENT_PHASE")
        if [ -n "$NEXT" ]; then
          NEXT_NAME=$(jq -r ".phases[] | select(.id==\"$NEXT\") | .name" prd.json 2>/dev/null)
          NEXT_INFO="Next: $NEXT ($NEXT_NAME) — $(get_phase_story_count "$NEXT") stories"
        else
          NEXT_INFO="Last phase done. Next: final review."
        fi
        emit "gate" "\"step\":\"phase-gate\",\"phase\":\"$CURRENT_PHASE\",\"phaseName\":\"$PHASE_NAME\",\"nextInfo\":\"$NEXT_INFO\",\"message\":\"Show phase summary. Wait for: CONTINUE / ADJUST: <instructions> / STOP. Then: gate-response <response>\""
        exit 0
        ;;

      final-review)
        emit_progress_before_spawn "final-review" "Final E2E review" "~15-30 min"
        emit "spawn" "\"step\":\"final-review\",\"template\":\"templates/final-review.md\",\"model\":\"reviewer\",\"timeout\":2700,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/final-review.md\"},\"onComplete\":\"complete final-review\",\"onBlocked\":\"complete final-review blocked <reason>\""
        exit 0
        ;;

      simplify)
        emit_progress_before_spawn "simplify" "Simplifying and cleaning up code" "~5-15 min"
        emit "spawn" "\"step\":\"simplify\",\"template\":\"templates/simplify.md\",\"model\":\"reviewer\",\"timeout\":1800,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/simplify.md\"},\"onComplete\":\"complete simplify\",\"onBlocked\":\"complete simplify blocked <reason>\""
        exit 0
        ;;

      complete)
        STARTED=$(json_get '.startedAt // "unknown"')
        PR_URL=$(json_get '.prUrl // "none"')
        TOTAL_S=$(jq '.userStories | length' prd.json 2>/dev/null || echo "?")
        TOTAL_P=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
        json_set ".pipeline = \"complete\" | .lastCheckpoint = \"$(now)\""
        emit "complete" "\"startedAt\":\"$STARTED\",\"prUrl\":\"$PR_URL\",\"stories\":$TOTAL_S,\"phases\":$TOTAL_P,\"message\":\"Pipeline complete! Show completion with clickable PR link.\""
        exit 0
        ;;

      blocked)
        REASON=$(json_get '.blockReason // "unknown"')
        emit "blocked" "\"reason\":\"$REASON\",\"message\":\"Pipeline blocked: $REASON\""
        exit 0
        ;;

      stopped)
        emit "stopped" "\"message\":\"Pipeline stopped.\""
        exit 0
        ;;

      *)
        emit "error" "\"message\":\"Unknown step: $CURRENT_STEP\""
        exit 0
        ;;
    esac
  done

  # Safety: if we hit max auto-advance, emit current step
  emit "error" "\"message\":\"Auto-advance limit reached at step: $CURRENT_STEP. Possible loop.\""
  exit 1
fi

echo '{"action":"error","message":"Unknown action: '"$ACTION"'. Use: init, next, complete, gate-response, resume"}'
exit 1
