#!/usr/bin/env bash
# quality-gate.sh — 3-tier quality gate system with baseline diffing.
# Runs progressively thorough checks depending on scope (story|phase|final).
# Uses project.json config (from detect-project.sh) to determine commands.
#
# Usage:
#   ./pipeline/quality-gate.sh --scope story|phase|final \
#       [--baseline capture|diff] [--config path/to/project.json] \
#       [--project-dir path] [--skip-docker]

set -u

# ─── Globals ──────────────────────────────────────────────────────────────────

SCOPE=""
BASELINE_MODE=""
CONFIG_PATH=""
PROJECT_DIR=""
SKIP_DOCKER=false

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
TOTAL_PREEXISTING=0
FAILURE_LOG=""

# ─── Auto-detect HOUSTON_DIR from script location ────────────────────────────

if [[ -z "${HOUSTON_DIR:-}" ]]; then
    HOUSTON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# ─── Parse arguments ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            SCOPE="$2"; shift 2 ;;
        --baseline)
            BASELINE_MODE="$2"; shift 2 ;;
        --config)
            CONFIG_PATH="$2"; shift 2 ;;
        --project-dir)
            PROJECT_DIR="$2"; shift 2 ;;
        --skip-docker)
            SKIP_DOCKER=true; shift ;;
        *)
            echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ─── Validate scope ──────────────────────────────────────────────────────────

if [[ -z "$SCOPE" ]]; then
    echo "ERROR: --scope is required (story|phase|final)" >&2
    exit 1
fi

case "$SCOPE" in
    story|phase|final) ;;
    *)
        echo "ERROR: --scope must be story, phase, or final (got: $SCOPE)" >&2
        exit 1 ;;
esac

# ─── Resolve project directory ────────────────────────────────────────────────

if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ─── Load config ──────────────────────────────────────────────────────────────

load_config() {
    local config_file="$1"

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required to parse config JSON" >&2
        exit 1
    fi

    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Config file not found: $config_file" >&2
        exit 1
    fi

    CFG_TEST_CMD="$(jq -r '.testCmd // empty' "$config_file")"
    CFG_TEST_CMD_ROOT="$(jq -r '.testCmdRoot // empty' "$config_file")"
    CFG_TYPECHECK_CMD="$(jq -r '.typecheckCmd // empty' "$config_file")"
    CFG_TYPECHECK_CMD_ROOT="$(jq -r '.typecheckCmdRoot // empty' "$config_file")"
    CFG_BUILD_CMD="$(jq -r '.buildCmd // empty' "$config_file")"
    CFG_LINT_CMD="$(jq -r '.lintCmd // empty' "$config_file")"
    CFG_E2E_CMD="$(jq -r '.e2eCmd // empty' "$config_file")"
    CFG_DOCKER_BUILD_CMD="$(jq -r '.dockerBuildCmd // empty' "$config_file")"
    CFG_DOCKER="$(jq -r '.docker // false' "$config_file")"
    CFG_MONOREPO="$(jq -r '.monorepo // false' "$config_file")"
    CFG_SKIP_TEST_PATTERN="$(jq -r '.skipTestPattern // empty' "$config_file")"
}

if [[ -n "$CONFIG_PATH" ]]; then
    load_config "$CONFIG_PATH"
else
    # Run detect-project.sh and load from its output
    DETECT_SCRIPT="${HOUSTON_DIR}/pipeline/detect-project.sh"
    if [[ ! -x "$DETECT_SCRIPT" ]]; then
        echo "ERROR: detect-project.sh not found or not executable at $DETECT_SCRIPT" >&2
        exit 1
    fi
    TEMP_CONFIG="$(mktemp)"
    trap 'rm -f "$TEMP_CONFIG"' EXIT
    if ! bash "$DETECT_SCRIPT" "$PROJECT_DIR" > "$TEMP_CONFIG"; then
        echo "ERROR: detect-project.sh failed" >&2
        exit 1
    fi
    load_config "$TEMP_CONFIG"
fi

# ─── Auto-detect baseline mode ───────────────────────────────────────────────

BASELINE_FILE="${PROJECT_DIR}/.baseline-failures.txt"

if [[ -z "$BASELINE_MODE" && -f "$BASELINE_FILE" ]]; then
    BASELINE_MODE="diff"
fi

# For baseline capture, force phase scope
if [[ "$BASELINE_MODE" == "capture" ]]; then
    SCOPE="phase"
fi

# ─── Baseline helpers ─────────────────────────────────────────────────────────

baseline_is_preexisting() {
    local gate_name="$1"
    if [[ "$BASELINE_MODE" == "diff" && -f "$BASELINE_FILE" ]]; then
        if grep -qF "[${gate_name}]" "$BASELINE_FILE" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# ─── Gate runner ──────────────────────────────────────────────────────────────

# run_gate NAME COMMAND
# Runs a command in a subshell, captures exit code, logs result.
run_gate() {
    local name="$1"
    local cmd="$2"

    if [[ -z "$cmd" ]]; then
        echo "SKIP [${name}] — no command configured"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        return
    fi

    local exit_code=0
    # Run in subshell so failures don't propagate
    (
        cd "$PROJECT_DIR"
        eval "$cmd"
    ) > /dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "PASS [${name}] — ${cmd} (exit 0)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        if baseline_is_preexisting "$name"; then
            echo "WARN [${name}] — ${cmd} (exit ${exit_code}) [pre-existing]"
            TOTAL_PREEXISTING=$((TOTAL_PREEXISTING + 1))
        else
            echo "FAIL [${name}] — ${cmd} (exit ${exit_code})"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            FAILURE_LOG="${FAILURE_LOG}[${name}] ${cmd} (exit ${exit_code})"$'\n'
        fi
    fi
}

# ─── Anti-pattern scan ────────────────────────────────────────────────────────

# scan_anti_patterns MODE
#   MODE=changed  — scan only git-changed files
#   MODE=full     — scan all tracked files
scan_anti_patterns() {
    local mode="${1:-changed}"
    local issues=0
    local output=""
    local files=""

    cd "$PROJECT_DIR"

    # Get file list
    if [[ "$mode" == "changed" ]]; then
        files="$(git diff --name-only --diff-filter=d HEAD 2>/dev/null || true)"
        if [[ -z "$files" ]]; then
            # Also check staged changes
            files="$(git diff --cached --name-only --diff-filter=d 2>/dev/null || true)"
        fi
        if [[ -z "$files" ]]; then
            echo "SKIP [anti-patterns] — no changed files to scan"
            TOTAL_SKIP=$((TOTAL_SKIP + 1))
            return
        fi
    else
        files="$(git ls-files 2>/dev/null || true)"
        if [[ -z "$files" ]]; then
            echo "SKIP [anti-patterns] — no tracked files to scan"
            TOTAL_SKIP=$((TOTAL_SKIP + 1))
            return
        fi
    fi

    local rules_file="${HOUSTON_DIR}/rules/anti-patterns.json"

    if [[ -f "$rules_file" ]] && command -v jq &>/dev/null; then
        # Parse rules from JSON
        local rule_count
        rule_count="$(jq 'length' "$rules_file")"

        local i=0
        while [[ $i -lt $rule_count ]]; do
            local pattern severity message
            pattern="$(jq -r ".[$i].pattern" "$rules_file")"
            message="$(jq -r ".[$i].message" "$rules_file")"
            severity="$(jq -r ".[$i].severity" "$rules_file")"

            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                [[ ! -f "$file" ]] && continue
                local matches
                matches="$(grep -nE "$pattern" "$file" 2>/dev/null || true)"
                if [[ -n "$matches" ]]; then
                    while IFS= read -r match_line; do
                        output="${output}  ${severity^^}: ${file}:${match_line} — ${message}"$'\n'
                        issues=$((issues + 1))
                    done <<< "$matches"
                fi
            done <<< "$files"

            i=$((i + 1))
        done
    else
        # Fallback: basic scan for console.log and .skip()
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ ! -f "$file" ]] && continue

            local matches
            matches="$(grep -nE 'console\.log' "$file" 2>/dev/null || true)"
            if [[ -n "$matches" ]]; then
                while IFS= read -r match_line; do
                    output="${output}  WARNING: ${file}:${match_line} — Use logger instead of console.log"$'\n'
                    issues=$((issues + 1))
                done <<< "$matches"
            fi

            matches="$(grep -nE '\.skip\(' "$file" 2>/dev/null || true)"
            if [[ -n "$matches" ]]; then
                while IFS= read -r match_line; do
                    output="${output}  ERROR: ${file}:${match_line} — No skipped tests"$'\n'
                    issues=$((issues + 1))
                done <<< "$matches"
            fi
        done <<< "$files"
    fi

    if [[ $issues -eq 0 ]]; then
        echo "PASS [anti-patterns] — 0 issues found"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        if [[ -n "$output" ]]; then
            printf '%s' "$output" >&2
        fi
        if baseline_is_preexisting "anti-patterns"; then
            echo "WARN [anti-patterns] — ${issues} issues found [pre-existing]"
            TOTAL_PREEXISTING=$((TOTAL_PREEXISTING + 1))
        else
            echo "FAIL [anti-patterns] — ${issues} issues found"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            FAILURE_LOG="${FAILURE_LOG}[anti-patterns] ${issues} issues found"$'\n'
        fi
    fi
}

# ─── Determine commands for test scope ────────────────────────────────────────

resolve_test_cmd() {
    local scope="$1"
    if [[ "$scope" == "story" && "$CFG_MONOREPO" == "true" && -n "$CFG_TEST_CMD" ]]; then
        # Story scope: package-level test if possible
        echo "$CFG_TEST_CMD"
    elif [[ "$scope" != "story" && "$CFG_MONOREPO" == "true" && -n "$CFG_TEST_CMD_ROOT" ]]; then
        # Phase/final scope in monorepo: root-level test
        echo "$CFG_TEST_CMD_ROOT"
    else
        echo "$CFG_TEST_CMD"
    fi
}

resolve_typecheck_cmd() {
    local scope="$1"
    if [[ "$scope" == "story" && -n "$CFG_TYPECHECK_CMD" ]]; then
        echo "$CFG_TYPECHECK_CMD"
    elif [[ "$scope" != "story" && "$CFG_MONOREPO" == "true" && -n "$CFG_TYPECHECK_CMD_ROOT" ]]; then
        echo "$CFG_TYPECHECK_CMD_ROOT"
    else
        echo "$CFG_TYPECHECK_CMD"
    fi
}

# ─── Run gates by scope ──────────────────────────────────────────────────────

run_story_gates() {
    local test_cmd
    test_cmd="$(resolve_test_cmd story)"
    local typecheck_cmd
    typecheck_cmd="$(resolve_typecheck_cmd story)"

    run_gate "tests" "$test_cmd"
    run_gate "typecheck" "$typecheck_cmd"
    scan_anti_patterns "changed"
}

run_phase_gates() {
    # Story gates first (with full test suite instead of package-level)
    local test_cmd
    test_cmd="$(resolve_test_cmd phase)"
    local typecheck_cmd
    typecheck_cmd="$(resolve_typecheck_cmd phase)"

    run_gate "tests" "$test_cmd"
    run_gate "typecheck" "$typecheck_cmd"
    run_gate "build" "$CFG_BUILD_CMD"
    run_gate "lint" "$CFG_LINT_CMD"
    scan_anti_patterns "changed"
}

run_final_gates() {
    # Phase gates first
    local test_cmd
    test_cmd="$(resolve_test_cmd final)"
    local typecheck_cmd
    typecheck_cmd="$(resolve_typecheck_cmd final)"

    run_gate "tests" "$test_cmd"
    run_gate "typecheck" "$typecheck_cmd"
    run_gate "build" "$CFG_BUILD_CMD"
    run_gate "lint" "$CFG_LINT_CMD"
    run_gate "e2e" "$CFG_E2E_CMD"

    # Docker build (unless skipped)
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        echo "SKIP [docker] — skipped via --skip-docker"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    elif [[ "$CFG_DOCKER" == "true" && -n "$CFG_DOCKER_BUILD_CMD" ]]; then
        run_gate "docker" "$CFG_DOCKER_BUILD_CMD"
    else
        echo "SKIP [docker] — no docker build configured"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi

    # Full anti-pattern scan
    scan_anti_patterns "full"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== HOUSTON QUALITY GATE (${SCOPE}) ==="
echo ""

case "$SCOPE" in
    story) run_story_gates ;;
    phase) run_phase_gates ;;
    final) run_final_gates ;;
esac

# ─── Baseline capture ────────────────────────────────────────────────────────

if [[ "$BASELINE_MODE" == "capture" ]]; then
    if [[ -n "$FAILURE_LOG" ]]; then
        printf '%s' "$FAILURE_LOG" > "$BASELINE_FILE"
        echo ""
        echo "Baseline captured: ${TOTAL_FAIL} failure(s) saved to ${BASELINE_FILE}"
    else
        # No failures — remove any stale baseline
        rm -f "$BASELINE_FILE"
        echo ""
        echo "Baseline captured: 0 failures (no baseline file needed)"
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo "=== RESULT: FAIL (${TOTAL_FAIL} gate failed, ${TOTAL_PREEXISTING} pre-existing) ==="
elif [[ $TOTAL_PREEXISTING -gt 0 ]]; then
    echo "=== RESULT: PASS (0 new failures, ${TOTAL_PREEXISTING} pre-existing) ==="
else
    echo "=== RESULT: PASS ==="
fi
echo ""

# Exit code: 0 = all pass (or only pre-existing), non-zero = new failures
if [[ $TOTAL_FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
