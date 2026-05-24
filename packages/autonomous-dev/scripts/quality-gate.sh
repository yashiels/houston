#!/bin/bash
# shellcheck disable=SC2034  # Some detected vars are used conditionally or by called scripts
# quality-gate.sh — Three-tier quality checks with baseline diffing
#
# Usage: ./scripts/quality-gate.sh [--scope story|phase|final] [--baseline capture|diff] [--skip-docker] [--skip-build] [--config path]
#
# Scopes:
#   story  — Fast per-story: package tests + ROOT typecheck
#   phase  — Thorough: FULL test suite (all packages) + root typecheck + build
#   final  — Everything: full tests + typecheck + build + docker + E2E + shortcut scan
#
# Baseline modes:
#   --baseline capture  — Run phase-scope gate, save results to .baseline-failures.txt
#   --baseline diff     — Compare current failures against baseline. New = FAIL, pre-existing = WARN.
#
# Default scope: phase | Default baseline: diff (if .baseline-failures.txt exists)
# Exit 0 = all gates pass (or only pre-existing failures), non-zero = new failures

set -u
# Note: NOT using set -e or pipefail — gates must run to completion even when individual commands fail.

# Resolve pipeline directory for sibling scripts
PIPELINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SCOPE="phase"
BASELINE_MODE=""
SKIP_DOCKER=false
SKIP_BUILD=false
CONFIG_FILE=""
FAILURES=0
NEW_FAILURES=0
BASELINE_FILE=".baseline-failures.txt"
GATE_LOG=$(mktemp)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --scope) SCOPE="$2"; shift ;;
    --baseline) BASELINE_MODE="$2"; shift ;;
    --skip-docker) SKIP_DOCKER=true ;;
    --skip-build) SKIP_BUILD=true ;;
    --config) CONFIG_FILE="$2"; shift ;;
    *) echo "Unknown option: $1" >&2 ;;
  esac
  shift
done

# Validate scope
case "$SCOPE" in
  story|phase|final) ;;
  *) echo "ERROR: Invalid scope '$SCOPE'. Use: story, phase, final" >&2; exit 1 ;;
esac

# ─── BASELINE CAPTURE MODE ───

if [ "$BASELINE_MODE" = "capture" ]; then
  echo "=== BASELINE CAPTURE ==="
  echo "Running phase-scope gate to establish baseline..."
  echo ""

  CAPTURE_OUTPUT=$("$0" --scope phase 2>&1) || true
  CAPTURE_EXIT=$?

  echo "$CAPTURE_OUTPUT" | grep "^FAIL \[" > "$BASELINE_FILE" 2>/dev/null || true
  FAIL_COUNT=$(wc -l < "$BASELINE_FILE" | tr -d ' ')

  echo "$CAPTURE_OUTPUT" > .baseline-gate.log

  echo "$CAPTURE_OUTPUT"
  echo ""
  echo "=== BASELINE CAPTURED ==="
  echo "Exit code: $CAPTURE_EXIT"
  echo "Known failures: $FAIL_COUNT (saved to $BASELINE_FILE)"
  echo "Full log: .baseline-gate.log"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "WARNING: Pre-existing failures detected. Workers will be warned but not blocked by these."
    echo "The researcher should review .baseline-gate.log for constraints."
  fi

  rm -f "$GATE_LOG"
  exit 0
fi

# ─── Load config ───

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(jq -r '.testCmd // ""' "$CONFIG_FILE")
  TEST_CMD_ROOT=$(jq -r '.testCmdRoot // .testCmd // ""' "$CONFIG_FILE")
  TYPECHECK_CMD=$(jq -r '.typecheckCmd // ""' "$CONFIG_FILE")
  TYPECHECK_CMD_ROOT=$(jq -r '.typecheckCmdRoot // .typecheckCmd // ""' "$CONFIG_FILE")
  BUILD_CMD=$(jq -r '.buildCmd // ""' "$CONFIG_FILE")
  LINT_CMD=$(jq -r '.lintCmd // ""' "$CONFIG_FILE")
  DOCKER_BUILD_CMD=$(jq -r '.dockerBuildCmd // ""' "$CONFIG_FILE")
  E2E_CMD=$(jq -r '.e2eCmd // ""' "$CONFIG_FILE")
  TYPESCRIPT=$(jq -r '.typescript // false' "$CONFIG_FILE")
  DOCKER=$(jq -r '.docker // false' "$CONFIG_FILE")
  MONOREPO=$(jq -r '.monorepo // false' "$CONFIG_FILE")
  LANG=$(jq -r '.lang // "unknown"' "$CONFIG_FILE")
  LOCKFILE_PATTERN=$(jq -r '.lockfilePattern // ""' "$CONFIG_FILE")
  SKIP_TEST_PATTERN=$(jq -r '.skipTestPattern // ""' "$CONFIG_FILE")
  TEST_FILE_PATTERN=$(jq -r '.testFilePattern // ""' "$CONFIG_FILE")
else
  DETECT_OUTPUT=$($PIPELINE_DIR/scripts/detect-project.sh 2>/dev/null || echo "{}")
  TEST_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.testCmd // ""')
  TEST_CMD_ROOT=$(echo "$DETECT_OUTPUT" | jq -r '.testCmdRoot // .testCmd // ""')
  TYPECHECK_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.typecheckCmd // ""')
  TYPECHECK_CMD_ROOT=$(echo "$DETECT_OUTPUT" | jq -r '.typecheckCmdRoot // .typecheckCmd // ""')
  BUILD_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.buildCmd // ""')
  LINT_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.lintCmd // ""')
  DOCKER_BUILD_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.dockerBuildCmd // ""')
  E2E_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.e2eCmd // ""')
  TYPESCRIPT=$(echo "$DETECT_OUTPUT" | jq -r '.typescript // false')
  DOCKER=$(echo "$DETECT_OUTPUT" | jq -r '.docker // false')
  MONOREPO=$(echo "$DETECT_OUTPUT" | jq -r '.monorepo // false')
  LANG=$(echo "$DETECT_OUTPUT" | jq -r '.lang // "unknown"')
  LOCKFILE_PATTERN=$(echo "$DETECT_OUTPUT" | jq -r '.lockfilePattern // ""')
  SKIP_TEST_PATTERN=$(echo "$DETECT_OUTPUT" | jq -r '.skipTestPattern // ""')
  TEST_FILE_PATTERN=$(echo "$DETECT_OUTPUT" | jq -r '.testFilePattern // ""')
fi

if [ "$MONOREPO" = "false" ]; then
  TEST_CMD_ROOT="$TEST_CMD"
  TYPECHECK_CMD_ROOT="$TYPECHECK_CMD"
fi

# ─── Gate runner ───

run_gate() {
  local name="$1"
  local cmd="$2"

  if [ -z "$cmd" ]; then
    echo "SKIP [$name] — no command configured"
    return 0
  fi

  echo ""
  echo "=== GATE: $name ==="
  echo "CMD: $cmd"

  ( eval "$cmd" ) 2>&1
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "PASS [$name]"
    echo "PASS [$name]" >> "$GATE_LOG"
    return 0
  else
    echo "FAIL [$name]"
    echo "FAIL [$name]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

echo "Quality Gate Run — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Scope: $SCOPE | Baseline: $([ -f "$BASELINE_FILE" ] && echo "available ($(wc -l < "$BASELINE_FILE" | tr -d ' ') known failures)" || echo "none")"
echo ""

# ─── GATE 1: Tests ───

case "$SCOPE" in
  story)
    run_gate "Tests (package)" "$TEST_CMD" || true
    ;;
  phase|final)
    run_gate "Tests (full project)" "$TEST_CMD_ROOT" || true
    ;;
esac

# ─── GATE 2: Type checking ───

if [ -n "${TYPECHECK_CMD_ROOT:-}" ] && [ "$TYPECHECK_CMD_ROOT" != "" ]; then
  run_gate "Typecheck" "$TYPECHECK_CMD_ROOT" || true
else
  echo ""
  echo "SKIP [Typecheck] — no typecheck command for ${LANG:-unknown}"
fi

# ─── GATE 2b: Lint ───

if [ -n "${LINT_CMD:-}" ] && [ "$LINT_CMD" != "" ]; then
  run_gate "Lint" "$LINT_CMD" || true
fi

# ─── GATE 3: Lockfile ───

echo ""
echo "=== GATE: Lockfile ==="
DEFAULT_LOCKFILE_PATTERN="package-lock\\.json|yarn\\.lock|pnpm-lock\\.yaml|bun\\.lock|Cargo\\.lock|go\\.sum|poetry\\.lock|Pipfile\\.lock|pubspec\\.lock|mix\\.lock"
LOCKFILE_CHANGES=$(git diff --name-only 2>/dev/null | grep -E "${LOCKFILE_PATTERN:-$DEFAULT_LOCKFILE_PATTERN}" || true)
if [ -n "$LOCKFILE_CHANGES" ]; then
  echo "WARN [Lockfile] — lockfile has uncommitted changes: $LOCKFILE_CHANGES"
else
  echo "PASS [Lockfile]"
fi

# ─── GATE 4: Build (phase + final) ───

if [ "$SCOPE" = "story" ]; then
  echo ""
  echo "SKIP [Build] — story scope"
elif [ "$SKIP_BUILD" = "true" ]; then
  echo ""
  echo "SKIP [Build] — --skip-build passed"
else
  run_gate "Build" "$BUILD_CMD" || true
fi

# ─── GATE 5: Docker (final only) ───

if [ "$SCOPE" = "final" ] && [ "$DOCKER" = "true" ] && [ "$SKIP_DOCKER" = "false" ]; then
  run_gate "Docker Build" "$DOCKER_BUILD_CMD" || true
else
  echo ""
  echo "SKIP [Docker Build] — $SCOPE scope or --skip-docker"
fi

# ─── GATE 6: E2E (final only) ───

if [ "$SCOPE" = "final" ]; then
  run_gate "E2E Tests" "$E2E_CMD" || true
else
  echo ""
  echo "SKIP [E2E Tests] — $SCOPE scope (final only)"
fi

# ─── GATE 7: Anti-Pattern Scan (all scopes) ───

if [ -f "$PIPELINE_DIR/rules/anti-patterns.json" ]; then
  echo ""
  echo "=== GATE: Anti-Patterns ==="
  if $PIPELINE_DIR/scripts/anti-pattern-scan.sh 2>&1; then
    echo "PASS [Anti-Patterns]"
    echo "PASS [Anti-Patterns]" >> "$GATE_LOG"
  else
    echo "FAIL [Anti-Patterns]"
    echo "FAIL [Anti-Patterns]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo ""
  echo "SKIP [Anti-Patterns] — no anti-patterns.json"
fi

# ─── GATE 8: Wiring Check (phase + final) ───

if [ "$SCOPE" != "story" ] && [ -f "wiring-checklist.json" ]; then
  echo ""
  echo "=== GATE: Wiring Check ==="
  if $PIPELINE_DIR/scripts/wiring-check.sh 2>&1; then
    echo "PASS [Wiring]"
    echo "PASS [Wiring]" >> "$GATE_LOG"
  else
    echo "FAIL [Wiring]"
    echo "FAIL [Wiring]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
elif [ "$SCOPE" != "story" ]; then
  echo ""
  echo "SKIP [Wiring] — no wiring-checklist.json"
fi

# ─── GATE 9: Reachability Check (phase + final) ───

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: Reachability ==="
  if $PIPELINE_DIR/scripts/reachability-check.sh 2>&1; then
    echo "PASS [Reachability]"
    echo "PASS [Reachability]" >> "$GATE_LOG"
  else
    echo "FAIL [Reachability]"
    echo "FAIL [Reachability]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
fi

# ─── GATE 10: No Shortcuts (phase + final) ───

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: No Shortcuts ==="
  SKIP_PATTERN="${SKIP_TEST_PATTERN:-.skip|.only|xit(|xdescribe(|fdescribe(|fit(}"
  SKIP_TESTS=$(grep -rn "$SKIP_PATTERN" . 2>/dev/null | grep -v node_modules | grep -v ".git" | grep -v vendor | grep -v build | grep -v target | grep -v ".dart_tool" | grep -v ".gradle" | grep -v __pycache__ || true)
  if [ -n "$SKIP_TESTS" ]; then
    echo "FAIL [No Shortcuts] — skipped/focused tests found:"
    echo "$SKIP_TESTS"
    echo "FAIL [No Shortcuts]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [No Shortcuts]"
  fi
else
  echo ""
  echo "SKIP [No Shortcuts] — story scope"
fi

# ─── GATE 11: Project CI Scripts ───

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: Project CI Scripts ==="

  CI_SCRIPTS_RUN=0
  CI_SCRIPTS_FAIL=0

  for ci_script in \
    "scripts/check-devdep-imports.sh" \
    "scripts/check-imports.sh" \
    "scripts/lint-ci.sh" \
    "scripts/validate-ci.sh"; do
    FULL_PATH="$(pwd)/$ci_script"
    if [ -f "$FULL_PATH" ] && [ -x "$FULL_PATH" ]; then
      CI_SCRIPTS_RUN=$((CI_SCRIPTS_RUN + 1))
      SCRIPT_NAME=$(basename "$ci_script" .sh)
      if bash "$FULL_PATH" 2>&1; then
        echo "  PASS [$SCRIPT_NAME]"
      else
        echo "  FAIL [$SCRIPT_NAME]"
        CI_SCRIPTS_FAIL=$((CI_SCRIPTS_FAIL + 1))
      fi
    fi
  done

  if [ "$CI_SCRIPTS_RUN" -eq 0 ]; then
    echo "SKIP [Project CI Scripts] — no scripts found"
  elif [ "$CI_SCRIPTS_FAIL" -eq 0 ]; then
    echo "PASS [Project CI Scripts] — $CI_SCRIPTS_RUN script(s) passed"
    echo "PASS [Project CI Scripts]" >> "$GATE_LOG"
  else
    echo "FAIL [Project CI Scripts] — $CI_SCRIPTS_FAIL of $CI_SCRIPTS_RUN failed"
    echo "FAIL [Project CI Scripts]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo ""
  echo "SKIP [Project CI Scripts] — story scope"
fi

# ─── BASELINE DIFF ───

HAS_BASELINE=false
if [ -f "$BASELINE_FILE" ] && [ -s "$BASELINE_FILE" ]; then
  HAS_BASELINE=true
fi

if [ "$FAILURES" -gt 0 ] && [ "$HAS_BASELINE" = "true" ]; then
  echo ""
  echo "=== BASELINE DIFF ==="

  normalize_gate() {
    echo "$1" | sed 's/^FAIL \[//; s/ (.*)//; s/\]$//'
  }

  BASELINE_GATES=""
  while IFS= read -r line; do
    NORM=$(normalize_gate "$line")
    BASELINE_GATES="$BASELINE_GATES|$NORM"
  done < "$BASELINE_FILE"

  while IFS= read -r fail_line; do
    NORM=$(normalize_gate "$fail_line")
    if echo "$BASELINE_GATES" | grep -qF "$NORM"; then
      echo "WARNING: PRE-EXISTING: $fail_line (baseline has $NORM failure)"
    else
      echo "ERROR: NEW FAILURE: $fail_line (not in baseline)"
      NEW_FAILURES=$((NEW_FAILURES + 1))
    fi
  done < <(grep "^FAIL" "$GATE_LOG" 2>/dev/null || true)

  echo ""
  echo "Baseline failures: $(grep -c "^FAIL" "$BASELINE_FILE" 2>/dev/null || echo 0)"
  echo "New failures: $NEW_FAILURES"
fi

# ─── SUMMARY ───

echo ""
echo "=== SUMMARY ($SCOPE scope) ==="
echo "Gates run:"
case "$SCOPE" in
  story)  echo "  Package tests | Root typecheck | Lockfile | Anti-patterns" ;;
  phase)  echo "  Full tests | Root typecheck | Lint | Lockfile | Build | Anti-patterns | Wiring | Reachability | No shortcuts | CI scripts" ;;
  final)  echo "  Full tests | Root typecheck | Lint | Lockfile | Build | Docker | E2E | Anti-patterns | Wiring | Reachability | No shortcuts | CI scripts" ;;
esac

rm -f "$GATE_LOG"

if [ "$FAILURES" -eq 0 ]; then
  echo "ALL GATES PASSED"
  exit 0
elif [ "$HAS_BASELINE" = "true" ] && [ "$NEW_FAILURES" -eq 0 ]; then
  echo "PASSED (only pre-existing failures, no new regressions)"
  exit 0
else
  if [ "$HAS_BASELINE" = "true" ]; then
    echo "FAILED: $NEW_FAILURES new failure(s) (plus $(($FAILURES - $NEW_FAILURES)) pre-existing)"
  else
    echo "FAILED: $FAILURES gate(s) failed"
  fi
  exit 1
fi
