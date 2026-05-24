#!/usr/bin/env bash
# shellcheck disable=SC2034  # Many variables are used by TUI functions or sourced configs
set -euo pipefail

# ─── Constants ──────────────────────────────────────────
AD_VERSION="1.0.0"
AD_DIR="$(cd "$(dirname "$0")" && pwd)"
AD_STATE_DIR=".autonomous-dev"
AD_LLM_CLI="${AD_LLM_CLI:-claude}"

# ─── Colors & Symbols ──────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'    DIM='\033[2m'     RESET='\033[0m'
  RED='\033[31m'    GREEN='\033[32m'  YELLOW='\033[33m'
  BLUE='\033[34m'   MAGENTA='\033[35m' CYAN='\033[36m'
  WHITE='\033[97m'  BG_BLUE='\033[44m' BG_GREEN='\033[42m'
  BG_MAGENTA='\033[45m' BG_RED='\033[41m' BG_YELLOW='\033[43m'
else
  BOLD='' DIM='' RESET='' RED='' GREEN='' YELLOW=''
  BLUE='' MAGENTA='' CYAN='' WHITE='' BG_BLUE='' BG_GREEN=''
  BG_MAGENTA='' BG_RED='' BG_YELLOW=''
fi

SYM_CHECK="✓" SYM_CROSS="✗" SYM_ARROW="→" SYM_BULLET="•"
SYM_GEAR="⚙" SYM_ROCKET="🚀" SYM_BRAIN="🧠" SYM_FLASK="🔬"
SYM_HAMMER="🔨" SYM_MAG="🔍" SYM_SHIELD="🛡" SYM_CHART="📊"
SYM_LINK="🔗" SYM_CLOCK="⏱" SYM_BLOCK="🚫"

# ─── Helpers ────────────────────────────────────────────
print_header() {
  local width=56
  echo ""
  echo -e "${BOLD}${CYAN}  ┌$( printf '─%.0s' $(seq 1 $width) )┐${RESET}"
  echo -e "${BOLD}${CYAN}  │${RESET}${BOLD}${WHITE}   ⚡ autonomous-dev ${DIM}v${AD_VERSION}${RESET}${BOLD}${CYAN}$(printf ' %.0s' $(seq 1 33))│${RESET}"
  echo -e "${BOLD}${CYAN}  │${RESET}${DIM}   PRD → Research → Plan → Code → Review → PR${RESET}${BOLD}${CYAN}     │${RESET}"
  echo -e "${BOLD}${CYAN}  └$( printf '─%.0s' $(seq 1 $width) )┘${RESET}"
  echo ""
}

print_step() {
  local icon="$1" label="$2"
  echo -e "  ${BOLD}${icon}  ${label}${RESET}"
}

print_ok() {
  echo -e "  ${GREEN}${SYM_CHECK}${RESET}  $1"
}

print_warn() {
  echo -e "  ${YELLOW}!${RESET}  $1"
}

print_fail() {
  echo -e "  ${RED}${SYM_CROSS}${RESET}  $1"
}

print_info() {
  echo -e "  ${DIM}${SYM_BULLET}${RESET}  $1"
}

print_divider() {
  echo -e "  ${DIM}$(printf '─%.0s' $(seq 1 52))${RESET}"
}

print_box() {
  local title="$1"; shift
  local pad_len=$(( 48 - ${#title} ))
  if [[ $pad_len -lt 0 ]]; then pad_len=0; fi
  echo ""
  echo -e "  ${BOLD}${CYAN}┌─ ${title} $( printf '─%.0s' $(seq 1 $(( pad_len > 0 ? pad_len : 1 )) ) )┐${RESET}"
  while [[ $# -gt 0 ]]; do
    echo -e "  ${CYAN}│${RESET}  $1"
    shift
  done
  echo -e "  ${CYAN}└$( printf '─%.0s' $(seq 1 52) )┘${RESET}"
  echo ""
}

prompt_choice() {
  local prompt="$1"
  echo -en "  ${BOLD}${WHITE}${prompt}${RESET} "
  read -r REPLY
  echo "$REPLY"
}

# ─── Preflight Checks ──────────────────────────────────
preflight() {
  local ok=true

  echo -e "  ${DIM}Checking requirements...${RESET}"
  echo ""

  # LLM CLI
  if command -v "$AD_LLM_CLI" &>/dev/null; then
    if [[ "$AD_LLM_CLI" == "claude" ]]; then
      local claude_ver
      claude_ver=$("$AD_LLM_CLI" --version 2>/dev/null | head -1 || echo "unknown")
      print_ok "${AD_LLM_CLI} CLI ${DIM}(${claude_ver})${RESET}"
    else
      print_ok "${AD_LLM_CLI} CLI ${DIM}(generic mode)${RESET}"
    fi
  else
    print_fail "${AD_LLM_CLI} CLI not found"
    if [[ "$AD_LLM_CLI" == "claude" ]]; then
      echo -e "    ${DIM}Install: npm i -g @anthropic-ai/claude-code${RESET}"
    fi
    ok=false
  fi

  # jq
  if command -v jq &>/dev/null; then
    print_ok "jq"
  else
    print_fail "jq not found — install: ${BOLD}brew install jq${RESET}"
    ok=false
  fi

  # git
  if command -v git &>/dev/null; then
    print_ok "git"
  else
    print_fail "git not found"
    ok=false
  fi

  # Auth check (only for claude CLI)
  if [[ "$AD_LLM_CLI" == "claude" ]]; then
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
      print_ok "Auth: API key ${DIM}(ANTHROPIC_API_KEY)${RESET}"
    elif claude auth status 2>/dev/null | jq -e '.loggedIn == true' &>/dev/null; then
      local auth_email
      auth_email=$(claude auth status 2>/dev/null | jq -r '.email // "unknown"')
      print_ok "Auth: OAuth ${DIM}(${auth_email})${RESET}"
    else
      print_warn "Auth: not detected — run ${BOLD}claude auth login${RESET} or set ${BOLD}ANTHROPIC_API_KEY${RESET}"
      ok=false
    fi
  fi

  echo ""

  if [[ "$ok" != "true" ]]; then
    print_fail "Missing requirements. Fix the above and retry."
    exit 1
  fi
}

# ─── Config Loading ─────────────────────────────────────
load_config() {
  # Defaults
  AD_DEFAULT_MODE="supervised"
  AD_DEFAULT_PRESET="premium"
  AD_PERMISSION_MODE="prompt"
  AD_STEP_TIMEOUT=0
  AD_EXTRA_FLAGS=""
  AD_MODEL_RESEARCHER="" AD_MODEL_PLANNER="" AD_MODEL_CODER="" AD_MODEL_REVIEWER=""

  # Global config
  if [[ -f "$AD_DIR/config.sh" ]]; then
    # shellcheck disable=SC1090
    source "$AD_DIR/config.sh"
  elif [[ -f "${HOME}/.autonomous-dev/config.sh" ]]; then
    # shellcheck disable=SC1090
    source "${HOME}/.autonomous-dev/config.sh"
  fi

  # Project-level override
  if [[ -f "${PROJECT_PATH}/config.sh" ]]; then
    # shellcheck disable=SC1090
    source "${PROJECT_PATH}/config.sh"
  fi

  # Env var override for LLM CLI
  AD_LLM_CLI="${AD_LLM_CLI:-claude}"
}

# ─── Model Resolution ──────────────────────────────────
resolve_models() {
  local preset="$1"
  case "$preset" in
    budget)
      MODEL_RESEARCHER="haiku" MODEL_PLANNER="sonnet"
      MODEL_CODER="sonnet"     MODEL_REVIEWER="haiku" ;;
    balanced)
      MODEL_RESEARCHER="sonnet" MODEL_PLANNER="sonnet"
      MODEL_CODER="sonnet"      MODEL_REVIEWER="sonnet" ;;
    premium)
      MODEL_RESEARCHER="sonnet" MODEL_PLANNER="opus"
      MODEL_CODER="opus"        MODEL_REVIEWER="opus" ;;
    max)
      MODEL_RESEARCHER="opus" MODEL_PLANNER="opus"
      MODEL_CODER="opus"      MODEL_REVIEWER="opus" ;;
    custom)
      MODEL_RESEARCHER="${AD_MODEL_RESEARCHER:-sonnet}"
      MODEL_PLANNER="${AD_MODEL_PLANNER:-opus}"
      MODEL_CODER="${AD_MODEL_CODER:-opus}"
      MODEL_REVIEWER="${AD_MODEL_REVIEWER:-opus}" ;;
    *)
      print_fail "Unknown preset: $preset"
      exit 1 ;;
  esac
}

# ─── Mode Selection TUI ────────────────────────────────
select_mode() {
  if [[ -n "${SELECTED_MODE:-}" ]]; then return; fi

  # Non-interactive: use config default
  if [[ ! -t 0 ]] && [[ -n "${AD_DEFAULT_MODE:-}" ]]; then
    SELECTED_MODE="${AD_DEFAULT_MODE}"
    print_ok "Mode: ${BOLD}${SELECTED_MODE}${RESET} ${DIM}(from config)${RESET}"
    return
  fi

  print_box "Mode" \
    "${BOLD}1${RESET}  Supervised ${DIM}— pause after research & plan, then auto${RESET}" \
    "${BOLD}2${RESET}  Autonomous ${DIM}— full auto, stop on blockers only${RESET}" \
    "${BOLD}3${RESET}  Human Assisted ${DIM}— pause at every phase gate${RESET}"

  local choice
  choice=$(prompt_choice "Select mode [1]:")
  case "${choice:-1}" in
    1|"") SELECTED_MODE="supervised" ;;
    2)    SELECTED_MODE="autonomous" ;;
    3)    SELECTED_MODE="human-assisted" ;;
    *)    SELECTED_MODE="supervised" ;;
  esac

  print_ok "Mode: ${BOLD}${SELECTED_MODE}${RESET}"
}

# ─── Model Selection TUI ───────────────────────────────
select_models() {
  if [[ -n "${SELECTED_PRESET:-}" ]]; then return; fi

  # Non-interactive: use config default
  if [[ ! -t 0 ]] && [[ -n "${AD_DEFAULT_PRESET:-}" ]]; then
    SELECTED_PRESET="${AD_DEFAULT_PRESET}"
    resolve_models "$SELECTED_PRESET"
    print_ok "Preset: ${BOLD}${SELECTED_PRESET}${RESET} ${DIM}(from config)${RESET}"
    print_info "Researcher=${DIM}${MODEL_RESEARCHER}${RESET}  Planner=${DIM}${MODEL_PLANNER}${RESET}  Coder=${DIM}${MODEL_CODER}${RESET}  Reviewer=${DIM}${MODEL_REVIEWER}${RESET}"
    return
  fi

  print_box "Models" \
    "${BOLD}1${RESET}  budget ${DIM}— haiku/sonnet (fastest, cheapest)${RESET}" \
    "${BOLD}2${RESET}  balanced ${DIM}— sonnet everything${RESET}" \
    "${BOLD}3${RESET}  premium ${DIM}— opus coder + planner, sonnet research (default)${RESET}" \
    "${BOLD}4${RESET}  max ${DIM}— opus everything${RESET}" \
    "${BOLD}5${RESET}  custom ${DIM}— pick each role${RESET}"

  local choice
  choice=$(prompt_choice "Select preset [3]:")
  case "${choice:-3}" in
    1)    SELECTED_PRESET="budget" ;;
    2)    SELECTED_PRESET="balanced" ;;
    3|"") SELECTED_PRESET="premium" ;;
    4)    SELECTED_PRESET="max" ;;
    5)    select_custom_models; SELECTED_PRESET="custom" ;;
    *)    SELECTED_PRESET="premium" ;;
  esac

  resolve_models "$SELECTED_PRESET"

  print_ok "Preset: ${BOLD}${SELECTED_PRESET}${RESET}"
  print_info "Researcher=${DIM}${MODEL_RESEARCHER}${RESET}  Planner=${DIM}${MODEL_PLANNER}${RESET}  Coder=${DIM}${MODEL_CODER}${RESET}  Reviewer=${DIM}${MODEL_REVIEWER}${RESET}"
}

select_custom_models() {
  echo ""
  echo -e "  ${DIM}Options: opus, sonnet, haiku (or full model name)${RESET}"
  echo ""
  local r p c v
  r=$(prompt_choice "  Researcher [sonnet]:")
  p=$(prompt_choice "  Planner [opus]:")
  c=$(prompt_choice "  Coder [opus]:")
  v=$(prompt_choice "  Reviewer [opus]:")

  AD_MODEL_RESEARCHER="${r:-sonnet}"
  AD_MODEL_PLANNER="${p:-opus}"
  AD_MODEL_CODER="${c:-opus}"
  AD_MODEL_REVIEWER="${v:-opus}"
}

# ─── Project Detection ──────────────────────────────────
detect_project() {
  print_step "$SYM_MAG" "Detecting project..."
  echo ""

  PROJECT_NAME=$(basename "$PROJECT_PATH")
  PACKAGE_MANAGER="unknown" MONOREPO=false HAS_TYPESCRIPT=false HAS_DOCKER=false
  TEST_FRAMEWORK="unknown"

  # Package manager
  if [[ -f "$PROJECT_PATH/pnpm-lock.yaml" ]]; then PACKAGE_MANAGER="pnpm"
  elif [[ -f "$PROJECT_PATH/yarn.lock" ]]; then PACKAGE_MANAGER="yarn"
  elif [[ -f "$PROJECT_PATH/bun.lockb" ]] || [[ -f "$PROJECT_PATH/bun.lock" ]]; then PACKAGE_MANAGER="bun"
  elif [[ -f "$PROJECT_PATH/package-lock.json" ]]; then PACKAGE_MANAGER="npm"
  elif [[ -f "$PROJECT_PATH/Cargo.toml" ]]; then PACKAGE_MANAGER="cargo"
  elif [[ -f "$PROJECT_PATH/go.mod" ]]; then PACKAGE_MANAGER="go"
  elif [[ -f "$PROJECT_PATH/requirements.txt" ]] || [[ -f "$PROJECT_PATH/pyproject.toml" ]]; then PACKAGE_MANAGER="pip"
  fi

  # Monorepo
  if [[ -f "$PROJECT_PATH/pnpm-workspace.yaml" ]] || [[ -f "$PROJECT_PATH/lerna.json" ]] \
     || [[ -f "$PROJECT_PATH/turbo.json" ]] || [[ -f "$PROJECT_PATH/nx.json" ]]; then
    MONOREPO=true
  fi

  # TypeScript
  if [[ -f "$PROJECT_PATH/tsconfig.json" ]]; then HAS_TYPESCRIPT=true; fi

  # Docker
  if [[ -f "$PROJECT_PATH/Dockerfile" ]] || [[ -f "$PROJECT_PATH/docker-compose.yml" ]] \
     || [[ -f "$PROJECT_PATH/docker-compose.yaml" ]]; then
    HAS_DOCKER=true
  fi

  # Test framework
  if [[ -f "$PROJECT_PATH/vitest.config.ts" ]] || [[ -f "$PROJECT_PATH/vitest.config.js" ]]; then
    TEST_FRAMEWORK="vitest"
  elif [[ -f "$PROJECT_PATH/jest.config.ts" ]] || [[ -f "$PROJECT_PATH/jest.config.js" ]] \
       || [[ -f "$PROJECT_PATH/jest.config.cjs" ]]; then
    TEST_FRAMEWORK="jest"
  elif [[ -f "$PROJECT_PATH/pytest.ini" ]] || [[ -f "$PROJECT_PATH/pyproject.toml" ]]; then
    TEST_FRAMEWORK="pytest"
  fi

  print_info "Project: ${BOLD}${PROJECT_NAME}${RESET}"
  print_info "Package manager: ${PACKAGE_MANAGER}  |  Monorepo: ${MONOREPO}"
  print_info "TypeScript: ${HAS_TYPESCRIPT}  |  Docker: ${HAS_DOCKER}  |  Tests: ${TEST_FRAMEWORK}"
  echo ""
}

# ─── Install Hooks ──────────────────────────────────────
install_hooks() {
  local target_project="${1:-.}"
  local hooks_src="${AD_DIR}/hooks/.claude"

  if [[ ! -d "$hooks_src" ]]; then
    print_fail "No hooks/.claude directory found in autonomous-dev repo"
    exit 1
  fi

  local target_dir="${target_project}/.claude"
  mkdir -p "$target_dir"
  cp -R "${hooks_src}/"* "$target_dir/" 2>/dev/null || true

  print_ok "Hooks installed to ${target_dir}"
}

# ─── State Management ───────────────────────────────────
STATE_FILE=""

init_state() {
  mkdir -p "${PROJECT_PATH}/${AD_STATE_DIR}"/{research,memory}
  STATE_FILE="${PROJECT_PATH}/${AD_STATE_DIR}/state.json"
  LOG_FILE="${PROJECT_PATH}/${AD_STATE_DIR}/pipeline.log"

  # Add state dir to .gitignore if not present
  local gi="${PROJECT_PATH}/.gitignore"
  if [[ -f "$gi" ]]; then
    grep -qxF ".autonomous-dev/" "$gi" 2>/dev/null || echo '.autonomous-dev/' >> "$gi"
  else
    echo '.autonomous-dev/' > "$gi"
  fi

  if [[ -f "$STATE_FILE" ]]; then
    return 0  # Existing state — will handle resume
  fi

  # Fresh state
  cat > "$STATE_FILE" <<EOF
{
  "version": 1,
  "mode": "${SELECTED_MODE}",
  "preset": "${SELECTED_PRESET}",
  "models": {
    "researcher": "${MODEL_RESEARCHER}",
    "planner": "${MODEL_PLANNER}",
    "coder": "${MODEL_CODER}",
    "reviewer": "${MODEL_REVIEWER}"
  },
  "project": {
    "path": "${PROJECT_PATH}",
    "name": "${PROJECT_NAME}",
    "prd": "${PRD_PATH}",
    "packageManager": "${PACKAGE_MANAGER}",
    "monorepo": ${MONOREPO},
    "typescript": ${HAS_TYPESCRIPT},
    "docker": ${HAS_DOCKER},
    "testFramework": "${TEST_FRAMEWORK}"
  },
  "pipeline": {
    "step": "init",
    "branch": "",
    "phases": {},
    "stories": {},
    "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF
}

update_state() {
  local key="$1" value="$2"
  local tmp="${STATE_FILE}.tmp"
  if jq "$key = $value" "$STATE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    log_step "WARNING: update_state failed for $key"
  fi
}

get_state() {
  jq -r "$1" "$STATE_FILE"
}

log_step() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE"
}

# ─── Resume Detection ───────────────────────────────────
check_resume() {
  STATE_FILE="${PROJECT_PATH}/${AD_STATE_DIR}/state.json"
  if [[ ! -f "$STATE_FILE" ]]; then return 1; fi

  local step mode preset completed total
  step=$(get_state '.pipeline.step')
  mode=$(get_state '.mode')
  preset=$(get_state '.preset')

  if [[ "$step" == "complete" ]]; then
    print_warn "Previous run completed. Starting fresh."
    rm -rf "${PROJECT_PATH:?}/${AD_STATE_DIR:?}"
    return 1
  fi

  # Count completed stories
  completed=$(jq '[.pipeline.stories | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE")
  total=$(jq '[.pipeline.stories | to_entries[]] | length' "$STATE_FILE")

  print_box "Resume Detected" \
    "Step: ${BOLD}${step}${RESET}" \
    "Mode: ${mode}  |  Preset: ${preset}" \
    "Stories: ${completed}/${total} complete"

  local choice
  choice=$(prompt_choice "Resume? [Y/n/restart]:")
  case "${choice:-y}" in
    y|Y|"")
      SELECTED_MODE="$mode"
      SELECTED_PRESET="$preset"
      resolve_models "$SELECTED_PRESET"
      RESUME_STEP="$step"
      return 0 ;;
    restart)
      rm -rf "${PROJECT_PATH:?}/${AD_STATE_DIR:?}"
      return 1 ;;
    *)
      echo "Cancelled."
      exit 0 ;;
  esac
}

# ─── LLM Invocation ────────────────────────────────────
run_llm() {
  local role="$1" model="$2" prompt="$3" template="$4"
  shift 4
  local extra_tools=("$@")

  local max_attempts="${AD_MAX_RETRIES:-2}"
  local attempt=0
  local session_id=""

  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))

    # ── Generic (non-Claude) LLM mode ──
    if [[ "$AD_LLM_CLI" != "claude" ]]; then
      local tmpfile
      tmpfile=$(mktemp "${TMPDIR:-/tmp}/ad-prompt-XXXXXX.md")

      # Write system context + prompt to temp file
      if [[ -n "$template" ]] && [[ -f "${AD_DIR}/templates/${template}" ]]; then
        cat "${AD_DIR}/templates/${template}" > "$tmpfile"
        echo "" >> "$tmpfile"
        echo "---" >> "$tmpfile"
        echo "" >> "$tmpfile"
      fi
      echo "$prompt" >> "$tmpfile"

      log_step "INVOKE (generic) role=$role model=$model cli=$AD_LLM_CLI attempt=$attempt"

      local output exit_code=0
      output=$("$AD_LLM_CLI" "$tmpfile" 2>&1) || exit_code=$?
      rm -f "$tmpfile"

      log_step "EXIT_CODE=$exit_code attempt=$attempt"
      if [[ $exit_code -eq 0 ]]; then
        echo "$output"
        return 0
      fi

      if [[ $attempt -ge $max_attempts ]]; then
        log_step "FAILED (generic) role=$role after $attempt attempts"
        echo "$output"
        return $exit_code
      fi
      continue
    fi

    # ── Claude CLI mode ──
    local -a cmd=(claude)

    # Model
    cmd+=(--model "$model")

    # Template as system prompt addition
    if [[ -n "$template" ]] && [[ -f "${AD_DIR}/templates/${template}" ]]; then
      cmd+=(--append-system-prompt-file "${AD_DIR}/templates/${template}")
    fi

    # Tool permissions
    if [[ ${#extra_tools[@]} -gt 0 ]]; then
      cmd+=(--allowedTools)
      cmd+=("${extra_tools[@]}")
    fi

    # Permission mode
    case "${AD_PERMISSION_MODE}" in
      bypass) cmd+=(--dangerously-skip-permissions) ;;
      auto)   cmd+=(--permission-mode auto) ;;
      # prompt = default, no flag needed
    esac

    # Extra flags from config
    if [[ -n "${AD_EXTRA_FLAGS:-}" ]]; then
      # shellcheck disable=SC2206
      cmd+=($AD_EXTRA_FLAGS)
    fi

    # Output format
    cmd+=(--output-format json)

    # Resume from previous attempt if we have a session ID
    if [[ -n "$session_id" ]]; then
      cmd+=(--resume "$session_id")
      cmd+=(-p "Continue where you left off. Your previous session ran out of context or failed. Check git status and the state of files. If you already committed, output STORY_COMPLETE. Otherwise, finish the remaining work and commit.")
      log_step "RETRY attempt=$attempt session=$session_id"
    else
      cmd+=(-p "$prompt")
    fi

    log_step "INVOKE role=$role model=$model template=$template attempt=$attempt"

    local output exit_code=0
    if [[ "${AD_VERBOSE:-false}" == "true" ]]; then
      if [[ "${AD_STEP_TIMEOUT:-0}" -gt 0 ]]; then
        output=$(timeout "$AD_STEP_TIMEOUT" "${cmd[@]}" 2> >(tee -a "${LOG_FILE:-/dev/null}" >&2)) || exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
          log_step "TIMEOUT after ${AD_STEP_TIMEOUT}s"
          echo "ERROR: Step timed out after ${AD_STEP_TIMEOUT} seconds"
          return 124
        fi
      else
        output=$("${cmd[@]}" 2> >(tee -a "${LOG_FILE:-/dev/null}" >&2)) || exit_code=$?
      fi
    else
      if [[ "${AD_STEP_TIMEOUT:-0}" -gt 0 ]]; then
        output=$(timeout "$AD_STEP_TIMEOUT" "${cmd[@]}" 2>&1) || exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
          log_step "TIMEOUT after ${AD_STEP_TIMEOUT}s"
          echo "ERROR: Step timed out after ${AD_STEP_TIMEOUT} seconds"
          return 124
        fi
      else
        output=$("${cmd[@]}" 2>&1) || exit_code=$?
      fi
    fi

    log_step "EXIT_CODE=$exit_code attempt=$attempt"

    # Extract session ID for potential retry
    local new_session_id
    new_session_id=$(echo "$output" | jq -r '.session_id // empty' 2>/dev/null) || true
    if [[ -n "$new_session_id" ]]; then
      session_id="$new_session_id"
    fi

    # Success — extract result and return
    if [[ $exit_code -eq 0 ]]; then
      local result
      result=$(echo "$output" | jq -r '.result // empty' 2>/dev/null) || true
      if [[ -z "$result" ]]; then
        result="$output"
      fi
      echo "$result"
      return 0
    fi

    # Check if Claude ran out of context
    local is_context_error=false
    if echo "$output" | grep -qi "context\|token.*limit\|conversation.*too.*long\|max.*output" 2>/dev/null; then
      is_context_error=true
    fi

    # If not a context error or last attempt, fail
    if [[ "$is_context_error" != "true" ]] || [[ $attempt -ge $max_attempts ]]; then
      log_step "FAILED role=$role after $attempt attempts"
      echo "$output"
      return $exit_code
    fi

    # Context error with retries left — loop will resume
    print_warn "Context exhausted (attempt ${attempt}/${max_attempts}) — resuming session..."
    log_step "CONTEXT_EXHAUSTED attempt=$attempt — will resume"

  done
}

# ─── Quality Gate Wrapper ───────────────────────────────
run_quality_gate() {
  local gate_script="${AD_DIR}/scripts/quality-gate.sh"
  if [[ ! -x "$gate_script" ]]; then
    print_warn "Quality gate script not found at ${gate_script} — skipping"
    return 0
  fi

  local gate_exit=0
  "$gate_script" --project "$PROJECT_PATH" --state-dir "$AD_STATE_DIR" "$@" || gate_exit=$?
  return $gate_exit
}

# ─── Pipeline Steps ────────────────────────────────────

step_research() {
  print_step "$SYM_FLASK" "Research — auditing codebase..."
  echo ""
  log_step "START research"

  local prompt
  prompt="Audit this codebase thoroughly. Project path: ${PROJECT_PATH}

Your job: examine the codebase and produce a comprehensive findings document.

Write your findings to: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md

The document should cover:
1. Project structure and architecture
2. Key conventions (naming, patterns, test organization)
3. Dependencies and their versions
4. Existing test patterns and coverage
5. Build and deploy configuration
6. Potential risks or technical debt
7. Integration points (APIs, databases, external services)

Read the PRD at: ${PRD_PATH}
Identify which parts of the codebase are relevant to the PRD goals.
Note any constraints the PRD must work within.

When done, output: RESEARCH_COMPLETE"

  local result
  result=$(run_llm "researcher" "$MODEL_RESEARCHER" "$prompt" "researcher.md" \
    "Read" "Grep" "Glob" "Bash" "Write")

  if [[ -f "${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md" ]]; then
    print_ok "Research complete — findings written"
    update_state '.pipeline.step' '"research-done"'
    log_step "COMPLETE research"
  else
    print_fail "Research failed — no findings.md produced"
    echo -e "  ${DIM}Output:${RESET}"
    echo "$result" | head -20
    log_step "FAILED research"
    return 1
  fi
}

step_research_gate() {
  if [[ "$SELECTED_MODE" == "autonomous" ]]; then return 0; fi

  print_box "Research Review" \
    "Findings: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md" \
    "" \
    "Review the findings before planning begins."

  local choice
  choice=$(prompt_choice "Continue to planning? [Y/n/view]:")
  case "${choice:-y}" in
    y|Y|"") return 0 ;;
    view|v)
      echo ""
      cat "${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md" 2>/dev/null | head -80
      echo -e "\n  ${DIM}(showing first 80 lines)${RESET}\n"
      choice=$(prompt_choice "Continue to planning? [Y/n]:")
      case "${choice:-y}" in
        y|Y|"") return 0 ;;
        *) echo "Stopped."; exit 0 ;;
      esac ;;
    *) echo "Stopped."; exit 0 ;;
  esac
}

step_plan() {
  print_step "$SYM_BRAIN" "Planning — converting PRD to stories..."
  echo ""
  log_step "START planner"

  local findings=""
  if [[ -f "${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md" ]]; then
    findings="Research findings are at: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md — read them first."
  fi

  local prompt
  prompt="You are a technical planner. Convert the PRD into an implementation plan.

PRD location: ${PRD_PATH}
${findings}
Project path: ${PROJECT_PATH}

Create a prd.json file at: ${PROJECT_PATH}/${AD_STATE_DIR}/prd.json

The prd.json must follow this schema:
{
  \"name\": \"Project name\",
  \"branch\": \"feature/branch-name\",
  \"phases\": [
    {
      \"id\": \"PHASE-1\",
      \"name\": \"Phase name\",
      \"description\": \"What this phase accomplishes\"
    }
  ],
  \"stories\": [
    {
      \"id\": \"STORY-001\",
      \"phase\": \"PHASE-1\",
      \"title\": \"Story title\",
      \"description\": \"What to implement\",
      \"acceptanceCriteria\": [\"List of criteria\"],
      \"testStrategy\": \"How to test this\",
      \"estimatedMinutes\": 30,
      \"dependencies\": [],
      \"filesToModify\": [\"list/of/files.ts\"]
    }
  ]
}

Rules:
- Stories must be small enough to implement in a single session (max 45 min estimated)
- Each story must be independently testable
- Dependencies must be explicit (a story can depend on earlier stories)
- Order stories within phases by dependency
- Final story in final phase must be an integration story that verifies end-to-end wiring
- Use the research findings to identify the right file paths, conventions, and patterns

When done, output: PLANNER_COMPLETE"

  local result
  result=$(run_llm "planner" "$MODEL_PLANNER" "$prompt" "planner.md" \
    "Read" "Grep" "Glob" "Write" "Bash(find *)" "Bash(cat *)")

  if [[ -f "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json" ]]; then
    # Validate prd.json schema
    local validate_script="${AD_DIR}/scripts/validate-prd.sh"
    if [[ -x "$validate_script" ]]; then
      local validate_output validate_exit=0
      validate_output=$("$validate_script" "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json" 2>&1) || validate_exit=$?
      if [[ $validate_exit -ne 0 ]]; then
        print_fail "prd.json validation failed:"
        echo "$validate_output" | grep -E "^FAIL:" | while IFS= read -r line; do
          print_fail "  $line"
        done
        log_step "FAILED planner — prd.json validation errors"
        return 1
      fi
      print_ok "prd.json schema valid"
    fi

    local story_count phase_count
    story_count=$(jq '.stories | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
    phase_count=$(jq '.phases | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
    print_ok "Plan complete — ${story_count} stories across ${phase_count} phases"
    update_state '.pipeline.step' '"plan-done"'
    log_step "COMPLETE planner stories=${story_count} phases=${phase_count}"
  else
    print_fail "Planning failed — no prd.json produced"
    echo "$result" | head -20
    log_step "FAILED planner"
    return 1
  fi
}

step_plan_gate() {
  if [[ "$SELECTED_MODE" == "autonomous" ]]; then return 0; fi

  local story_count phase_count branch
  story_count=$(jq '.stories | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  phase_count=$(jq '.phases | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  branch=$(jq -r '.branch' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")

  # Show phase summary
  echo ""
  print_box "Plan Review" \
    "Branch: ${BOLD}${branch}${RESET}" \
    "Stories: ${story_count}  |  Phases: ${phase_count}" \
    "" \
    "$(jq -r '.phases[] | "  \(.id): \(.name)"' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")"

  local choice
  choice=$(prompt_choice "Proceed to implementation? [Y/n/view]:")
  case "${choice:-y}" in
    y|Y|"") return 0 ;;
    view|v)
      echo ""
      jq -r '.stories[] | "  \(.id) [\(.phase)] \(.title) (~\(.estimatedMinutes)min)"' \
        "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json"
      echo ""
      choice=$(prompt_choice "Proceed? [Y/n]:")
      case "${choice:-y}" in
        y|Y|"") return 0 ;;
        *) echo "Stopped."; exit 0 ;;
      esac ;;
    *) echo "Stopped."; exit 0 ;;
  esac
}

step_preflight() {
  local story_count phase_count branch est_minutes
  story_count=$(jq '.stories | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  phase_count=$(jq '.phases | length' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  branch=$(jq -r '.branch' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  est_minutes=$(jq '[.stories[].estimatedMinutes] | add' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
  local est_with_overhead=$(( est_minutes * 130 / 100 ))  # 30% overhead

  print_box "${SYM_ROCKET} Pre-Flight" \
    "Project:  ${BOLD}${PROJECT_NAME}${RESET}" \
    "Branch:   ${BOLD}${branch}${RESET}" \
    "Path:     ${DIM}${PROJECT_PATH}${RESET}" \
    "" \
    "Mode:     ${BOLD}${SELECTED_MODE}${RESET}" \
    "Preset:   ${BOLD}${SELECTED_PRESET}${RESET}" \
    "" \
    "Models:" \
    "  Researcher: ${MODEL_RESEARCHER}" \
    "  Planner:    ${MODEL_PLANNER}" \
    "  Coder:      ${MODEL_CODER}" \
    "  Reviewer:   ${MODEL_REVIEWER}" \
    "" \
    "Plan:     ${story_count} stories across ${phase_count} phases" \
    "Estimate: ~${est_with_overhead} min (${est_minutes} min + 30% overhead)"

  # Create branch
  (cd "$PROJECT_PATH" && git checkout -b "$branch" 2>/dev/null || git checkout "$branch" 2>/dev/null || true)
  update_state '.pipeline.branch' "\"$branch\""

  print_ok "Branch: ${branch}"
  update_state '.pipeline.step' '"coding"'
  log_step "PREFLIGHT branch=$branch stories=$story_count phases=$phase_count"
}

step_code() {
  print_step "$SYM_HAMMER" "Coding — implementing stories..."
  echo ""

  local prd="${PROJECT_PATH}/${AD_STATE_DIR}/prd.json"
  local stories phases current_phase=""

  stories=$(jq -r '.stories[].id' "$prd")
  phases=$(jq -r '.phases[].id' "$prd")

  for story_id in $stories; do
    # Check if already done (resume support)
    local story_status
    story_status=$(get_state ".pipeline.stories.\"${story_id}\".status // \"pending\"")
    if [[ "$story_status" == "complete" ]]; then
      print_ok "${story_id} — already done (resumed)"
      continue
    fi

    # Phase transition check
    local story_phase
    story_phase=$(jq -r ".stories[] | select(.id == \"$story_id\") | .phase" "$prd")
    if [[ "$story_phase" != "$current_phase" ]]; then
      if [[ -n "$current_phase" ]]; then
        step_phase_review "$current_phase"
      fi
      current_phase="$story_phase"
      local phase_name
      phase_name=$(jq -r ".phases[] | select(.id == \"$story_phase\") | .name" "$prd")
      echo ""
      print_divider
      print_step "$SYM_GEAR" "Phase: ${current_phase} — ${phase_name}"
      print_divider
      echo ""
    fi

    # Phase gate for human-assisted mode
    if [[ "$SELECTED_MODE" == "human-assisted" && -n "$current_phase" ]]; then
      local gate_status
      gate_status=$(get_state ".pipeline.phases.\"${current_phase}\".gateApproved // false")
      if [[ "$gate_status" != "true" ]]; then
        local choice
        choice=$(prompt_choice "Start ${current_phase}? [Y/n]:")
        case "${choice:-y}" in
          y|Y|"") update_state ".pipeline.phases.\"${current_phase}\".gateApproved" 'true' ;;
          *) echo "Stopped at phase gate."; exit 0 ;;
        esac
      fi
    fi

    # Extract story details
    local title desc criteria test_strategy est_min files_to_modify
    title=$(jq -r ".stories[] | select(.id == \"$story_id\") | .title" "$prd")
    desc=$(jq -r ".stories[] | select(.id == \"$story_id\") | .description" "$prd")
    criteria=$(jq -r ".stories[] | select(.id == \"$story_id\") | .acceptanceCriteria | join(\"\n- \")" "$prd")
    test_strategy=$(jq -r ".stories[] | select(.id == \"$story_id\") | .testStrategy" "$prd")
    est_min=$(jq -r ".stories[] | select(.id == \"$story_id\") | .estimatedMinutes" "$prd")
    files_to_modify=$(jq -r ".stories[] | select(.id == \"$story_id\") | .filesToModify | join(\", \")" "$prd")

    print_step "$SYM_ARROW" "${story_id}: ${title} ${DIM}(~${est_min}min)${RESET}"

    update_state ".pipeline.stories.\"${story_id}\".status" '"in_progress"'
    update_state ".pipeline.stories.\"${story_id}\".startedAt" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""

    local prompt
    prompt="Implement story ${story_id}: ${title}

Description: ${desc}

Acceptance Criteria:
- ${criteria}

Test Strategy: ${test_strategy}

Files likely to modify: ${files_to_modify}

Project path: ${PROJECT_PATH}
Research findings: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md
Cross-phase learnings: ${PROJECT_PATH}/${AD_STATE_DIR}/memory/learnings.md (read if exists, append learnings)

RULES:
1. Write tests FIRST, then implement code to pass them
2. Run tests after implementation to verify they pass
3. Do not modify tests to make them pass — fix the implementation
4. Commit your changes with message: \"${story_id}: ${title}\"
5. If you discover something important for future stories, append to ${PROJECT_PATH}/${AD_STATE_DIR}/memory/learnings.md

When done, output: STORY_COMPLETE
If blocked, output: STORY_BLOCKED: <reason>"

    local result exit_code=0
    result=$(run_llm "coder" "$MODEL_CODER" "$prompt" "coder.md" \
      "Bash" "Read" "Edit" "Write" "Grep" "Glob") || exit_code=$?

    if [[ $exit_code -ne 0 ]] || echo "$result" | grep -q "STORY_BLOCKED"; then
      local reason
      reason=$(echo "$result" | grep "STORY_BLOCKED" | sed 's/.*STORY_BLOCKED: //' || echo "Unknown error (exit code: $exit_code)")
      print_fail "${story_id} blocked: ${reason}"
      update_state ".pipeline.stories.\"${story_id}\".status" '"blocked"'
      update_state ".pipeline.stories.\"${story_id}\".reason" "\"${reason}\""
      update_state '.pipeline.step' "\"blocked-${story_id}\""
      log_step "BLOCKED ${story_id}: ${reason}"

      print_box "${SYM_BLOCK} Story Blocked" \
        "Story: ${story_id} — ${title}" \
        "Reason: ${reason}" \
        "" \
        "Fix the issue and re-run to resume."
      exit 1
    fi

    print_ok "${story_id} complete"
    update_state ".pipeline.stories.\"${story_id}\".status" '"complete"'
    update_state ".pipeline.stories.\"${story_id}\".completedAt" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    log_step "COMPLETE ${story_id}"

    # Run story-scope quality gate
    if ! run_quality_gate --scope story; then
      print_warn "${story_id} — quality gate failed, marking as blocked"
      update_state ".pipeline.stories.\"${story_id}\".status" '"blocked"'
      update_state ".pipeline.stories.\"${story_id}\".reason" '"Story quality gate failed"'
      log_step "QUALITY_GATE_FAIL ${story_id}"
    fi
  done

  # Final phase review
  if [[ -n "$current_phase" ]]; then
    step_phase_review "$current_phase"
  fi

  update_state '.pipeline.step' '"review"'
}

step_phase_review() {
  local phase_id="$1"
  local phase_name
  phase_name=$(jq -r ".phases[] | select(.id == \"$phase_id\") | .name" "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")

  echo ""
  print_step "$SYM_SHIELD" "Phase review: ${phase_id} — ${phase_name}"

  # Run phase-scope quality gate before reviewer
  if ! run_quality_gate --scope phase; then
    print_warn "Phase ${phase_id} quality gate found issues — reviewer will address them"
  fi

  local prompt
  prompt="Review the work done in phase ${phase_id} (${phase_name}).

Project path: ${PROJECT_PATH}
PRD: ${PROJECT_PATH}/${AD_STATE_DIR}/prd.json
Research: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md

Review checklist:
1. Read all stories in ${phase_id} from prd.json
2. Verify each story's acceptance criteria are met
3. Run the test suite — all tests must pass
4. Check for regressions
5. Verify code quality and conventions match the project
6. Add integration tests if stories interact with each other
7. Write a summary to: ${PROJECT_PATH}/${AD_STATE_DIR}/memory/phase-${phase_id}.md

If issues found, fix them and commit with: \"${phase_id}: review fixes\"

When done, output: REVIEW_COMPLETE
If blocked, output: REVIEW_BLOCKED: <reason>"

  local result
  result=$(run_llm "reviewer" "$MODEL_REVIEWER" "$prompt" "reviewer.md" \
    "Bash" "Read" "Edit" "Write" "Grep" "Glob")

  if echo "$result" | grep -q "REVIEW_BLOCKED"; then
    local reason
    reason=$(echo "$result" | grep "REVIEW_BLOCKED" | sed 's/.*REVIEW_BLOCKED: //')
    print_warn "Phase review flagged issues: ${reason}"
    log_step "REVIEW_WARN ${phase_id}: ${reason}"
  else
    print_ok "Phase ${phase_id} review passed"
    log_step "REVIEW_OK ${phase_id}"
  fi

  update_state ".pipeline.phases.\"${phase_id}\".status" '"reviewed"'
  update_state ".pipeline.phases.\"${phase_id}\".reviewedAt" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
}

step_final_review() {
  print_step "$SYM_SHIELD" "Final E2E review..."
  echo ""
  log_step "START final-review"

  # Run final-scope quality gate before reviewer
  if ! run_quality_gate --scope final; then
    print_warn "Final quality gate found issues — reviewer will address them"
  fi

  local prompt
  prompt="Perform a final end-to-end review of all changes.

Project path: ${PROJECT_PATH}
PRD: ${PROJECT_PATH}/${AD_STATE_DIR}/prd.json
Research: ${PROJECT_PATH}/${AD_STATE_DIR}/research/findings.md
Learnings: ${PROJECT_PATH}/${AD_STATE_DIR}/memory/learnings.md

Review:
1. Run the FULL test suite
2. If the project has a build step, run it
3. Verify all stories across all phases integrate correctly
4. Check that new code is reachable from entry points (not just tested)
5. Look for dead code, unused imports, leftover TODOs
6. Verify the changes match the original PRD intent
7. Fix any issues found and commit with: \"final-review: <description>\"

When done, output: FINAL_REVIEW_COMPLETE
If blocked, output: FINAL_REVIEW_BLOCKED: <reason>"

  local result
  result=$(run_llm "reviewer" "$MODEL_REVIEWER" "$prompt" "final-review.md" \
    "Bash" "Read" "Edit" "Write" "Grep" "Glob")

  if echo "$result" | grep -q "FINAL_REVIEW_BLOCKED"; then
    local reason
    reason=$(echo "$result" | grep "FINAL_REVIEW_BLOCKED" | sed 's/.*FINAL_REVIEW_BLOCKED: //')
    print_fail "Final review blocked: ${reason}"
    log_step "FINAL_REVIEW_BLOCKED: ${reason}"
    return 1
  fi

  print_ok "Final review passed"
  update_state '.pipeline.step' '"pr"'
  log_step "COMPLETE final-review"
}

step_create_pr() {
  print_step "$SYM_LINK" "Creating PR..."
  echo ""
  log_step "START pr-create"

  local branch prd_name
  branch=$(get_state '.pipeline.branch')
  prd_name=$(jq -r '.name' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")

  (cd "$PROJECT_PATH" && git push -u origin "$branch" 2>&1) || true

  local pr_url
  pr_url=$(cd "$PROJECT_PATH" && gh pr create \
    --title "$prd_name" \
    --body "Automated implementation via autonomous-dev.

## Changes
$(jq -r '.phases[] | "### \(.id): \(.name)\n\(.description)\n"' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")

## Stories Implemented
$(jq -r '.stories[] | "- [x] \(.id): \(.title)"' "${PROJECT_PATH}/${AD_STATE_DIR}/prd.json")
" \
    --head "$branch" 2>&1) || true

  if [[ -n "$pr_url" ]]; then
    print_ok "PR created"
    update_state '.pipeline.prUrl' "\"${pr_url}\""
  else
    print_warn "PR creation failed — push succeeded, create PR manually"
    pr_url="(manual)"
  fi

  update_state '.pipeline.step' '"ci_monitor"'
  log_step "COMPLETE pr-create url=${pr_url}"
}

step_ci_monitor() {
  # Skip if gh CLI not available
  if ! command -v gh &>/dev/null; then
    print_warn "gh CLI not found — skipping CI monitoring"
    return 0
  fi

  local pr_url
  pr_url=$(get_state '.pipeline.prUrl // ""')
  if [[ -z "$pr_url" ]] || [[ "$pr_url" == "(manual)" ]]; then
    print_warn "No PR URL available — skipping CI monitoring"
    return 0
  fi

  print_step "$SYM_CHART" "CI Monitoring — checking PR checks..."
  echo ""
  log_step "START ci-monitor"

  local max_rounds=3
  local round=0

  while [[ $round -lt $max_rounds ]]; do
    round=$((round + 1))

    # Wait a bit for CI to start on first check
    if [[ $round -eq 1 ]]; then
      print_info "Waiting 30s for CI to start..."
      sleep 30
    fi

    # Check PR status
    local checks_output checks_exit=0
    checks_output=$(cd "$PROJECT_PATH" && gh pr checks 2>&1) || checks_exit=$?

    if [[ $checks_exit -eq 0 ]]; then
      print_ok "All CI checks passed"
      log_step "CI_MONITOR passed"
      return 0
    fi

    # Check if checks are still pending
    if echo "$checks_output" | grep -qi "pending\|queued\|in_progress\|waiting"; then
      print_info "CI checks still running (round ${round}/${max_rounds}), waiting 60s..."
      sleep 60
      checks_output=$(cd "$PROJECT_PATH" && gh pr checks 2>&1) || checks_exit=$?
      if [[ $checks_exit -eq 0 ]]; then
        print_ok "All CI checks passed"
        log_step "CI_MONITOR passed after wait"
        return 0
      fi
    fi

    print_warn "CI checks failed (round ${round}/${max_rounds})"
    log_step "CI_MONITOR fail round=$round"

    if [[ $round -ge $max_rounds ]]; then
      break
    fi

    # Spawn LLM to fix CI failures
    print_info "Spawning ${AD_LLM_CLI} to fix CI failures..."

    local fix_prompt
    fix_prompt="CI checks are failing on this PR. Here is the output:

${checks_output}

Project path: ${PROJECT_PATH}

1. Read the CI failure output above
2. Identify and fix the issue
3. Run tests locally to verify
4. Commit the fix with message: \"ci: fix CI failure (round ${round})\"
5. Push to the current branch

When done, output: CI_FIX_COMPLETE
If unable to fix, output: CI_FIX_BLOCKED: <reason>"

    local fix_result
    fix_result=$(run_llm "coder" "$MODEL_CODER" "$fix_prompt" "coder.md" \
      "Bash" "Read" "Edit" "Write" "Grep" "Glob") || true

    # Push the fix
    (cd "$PROJECT_PATH" && git push 2>&1) || true

    # Wait for new CI run
    print_info "Waiting 60s for CI to re-run..."
    sleep 60
  done

  print_warn "CI checks still failing after ${max_rounds} fix rounds — continuing anyway"
  log_step "CI_MONITOR exhausted rounds=$max_rounds"
  return 0
}

step_complete() {
  local branch story_count pr_url started_at duration
  branch=$(get_state '.pipeline.branch')
  story_count=$(jq '[.pipeline.stories | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE")
  local total_stories
  total_stories=$(jq '.pipeline.stories | length' "$STATE_FILE")
  local phase_count
  phase_count=$(jq '.pipeline.phases | length' "$STATE_FILE")
  pr_url=$(get_state '.pipeline.prUrl // "(none)"')
  started_at=$(get_state '.pipeline.startedAt')

  # Calculate duration
  local started_epoch now_epoch
  started_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || date -d "$started_at" +%s 2>/dev/null || echo 0)
  now_epoch=$(date +%s)
  local elapsed_min=$(( (now_epoch - started_epoch) / 60 ))

  echo ""
  echo ""
  print_box "${SYM_CHECK} Complete" \
    "Project:  ${BOLD}${PROJECT_NAME}${RESET}" \
    "Branch:   ${BOLD}${branch}${RESET}" \
    "Stories:  ${story_count}/${total_stories}" \
    "Phases:   ${phase_count}" \
    "Duration: ~${elapsed_min} min"

  if [[ "$pr_url" != "(none)" ]]; then
    echo -e "  ${SYM_LINK}  ${BOLD}${pr_url}${RESET}"
  fi

  echo ""
  log_step "PIPELINE COMPLETE"
}

# ─── Main ───────────────────────────────────────────────
main() {
  # Parse flags
  AD_VERBOSE="${AD_VERBOSE:-false}"
  while [[ "${1:-}" == -* ]]; do
    case "$1" in
      -h|--help)
        echo "Usage: ac.sh [options] [project-path] [prd-file]"
        echo ""
        echo "Options:"
        echo "  -v, --verbose       Verbose output"
        echo "  --install-hooks DIR Copy Claude Code hooks to DIR/.claude/"
        echo "  -h, --help          Show this help"
        echo ""
        echo "Examples:"
        echo "  ac.sh .                    # Current dir, auto-find PRD"
        echo "  ac.sh /path/to/project     # Specific project"
        echo "  ac.sh . prd.md             # Specific PRD file"
        exit 0
        ;;
      -v|--verbose) AD_VERBOSE=true; shift ;;
      --install-hooks)
        shift
        local target="${1:-.}"
        shift || true
        install_hooks "$target"
        exit 0
        ;;
      *) break ;;
    esac
  done

  # Parse args
  PROJECT_PATH="${1:-.}"
  PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
  PRD_PATH="${2:-}"

  # Find PRD
  if [[ -z "$PRD_PATH" ]]; then
    for candidate in prd.md PRD.md prd.txt PRD.txt; do
      if [[ -f "${PROJECT_PATH}/${candidate}" ]]; then
        PRD_PATH="${PROJECT_PATH}/${candidate}"
        break
      fi
    done
  elif [[ ! "$PRD_PATH" = /* ]]; then
    PRD_PATH="${PROJECT_PATH}/${PRD_PATH}"
  fi

  print_header
  preflight

  # Check for resume
  RESUME_STEP=""
  SELECTED_MODE="" SELECTED_PRESET=""
  if check_resume; then
    print_ok "Resuming from: ${RESUME_STEP}"
  else
    # Fresh run — need PRD
    if [[ -z "$PRD_PATH" ]] || [[ ! -f "$PRD_PATH" ]]; then
      print_fail "No PRD found. Pass it as argument or place prd.md in your project root."
      echo -e "  ${DIM}Usage: ac.sh [project-path] [prd-path]${RESET}"
      exit 1
    fi

    load_config

    # Warn about dangerous permission bypass
    if [[ "${AD_PERMISSION_MODE}" == "bypass" ]]; then
      echo ""
      echo -e "  ${BG_RED}${WHITE}${BOLD}  WARNING: --dangerously-skip-permissions ENABLED  ${RESET}"
      echo -e "  ${RED}${BOLD}  The LLM CLI will execute ALL tool calls without confirmation.${RESET}"
      echo -e "  ${RED}${BOLD}  This includes file writes, deletes, and shell commands.${RESET}"
      echo -e "  ${DIM}  Set AD_PERMISSION_MODE=prompt or auto for safer operation.${RESET}"
      echo ""
      if [[ -t 0 ]]; then
        local bypass_choice
        bypass_choice=$(prompt_choice "Continue with skip-permissions? [y/N]:")
        case "${bypass_choice:-n}" in
          y|Y) print_warn "Proceeding with --dangerously-skip-permissions" ;;
          *)   echo "Cancelled."; exit 0 ;;
        esac
      fi
    fi

    select_mode
    select_models
    detect_project
    init_state

    # Capture quality baseline before any work begins
    run_quality_gate --baseline capture

    RESUME_STEP="research"
  fi

  # Pipeline loop — ordered steps with resume support
  local steps=(research research-done plan-done coding review pr ci_monitor complete)
  local started=false

  for step in "${steps[@]}"; do
    # Skip steps until we reach the resume point
    if [[ "$started" != "true" ]]; then
      case "$RESUME_STEP" in
        init|research)     [[ "$step" == "research" ]] && started=true ;;
        research-done)     [[ "$step" == "research-done" ]] && started=true ;;
        plan-done)         [[ "$step" == "plan-done" ]] && started=true ;;
        coding|blocked-*)  [[ "$step" == "coding" ]] && started=true ;;
        review)            [[ "$step" == "review" ]] && started=true ;;
        pr)                [[ "$step" == "pr" ]] && started=true ;;
        ci_monitor)        [[ "$step" == "ci_monitor" ]] && started=true ;;
        complete)          [[ "$step" == "complete" ]] && started=true ;;
        *)                 print_fail "Unknown pipeline step: ${RESUME_STEP}"; exit 1 ;;
      esac
      [[ "$started" != "true" ]] && continue
    fi

    case "$step" in
      research)      step_research ;;
      research-done) step_research_gate; step_plan ;;
      plan-done)     step_plan_gate; step_preflight ;;
      coding)        step_code ;;
      review)        step_final_review ;;
      pr)            step_create_pr ;;
      ci_monitor)    step_ci_monitor ;;
      complete)      step_complete ;;
    esac
  done
}

main "$@"
