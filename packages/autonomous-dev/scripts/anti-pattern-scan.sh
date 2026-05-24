#!/usr/bin/env bash
# anti-pattern-scan.sh — Scan changed files for common anti-patterns
# Usage: anti-pattern-scan.sh [--project-dir <path>] [base-ref]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR=""
BASE_REF=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-dir) PROJECT_DIR="$2"; shift; shift ;;
    *) BASE_REF="$1"; shift ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
BASE_REF="${BASE_REF:-HEAD~1}"

cd "$PROJECT_DIR"

ISSUES=0

CHANGED_TS="$(git diff --name-only "$BASE_REF" -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null || echo '')"

if [ -z "$CHANGED_TS" ]; then
    echo "No TypeScript/JavaScript changes to scan."
    exit 0
fi

echo "Scanning changed files for anti-patterns..."

# ── Pattern checks from anti-patterns.json ──
AP_FILE="$SCRIPT_DIR/../rules/anti-patterns.json"
if [ -f "$AP_FILE" ]; then
    AP_COUNT=$(jq length "$AP_FILE")
    for i in $(seq 0 $((AP_COUNT - 1))); do
        PATTERN=$(jq -r ".[$i].pattern" "$AP_FILE")
        MESSAGE=$(jq -r ".[$i].message" "$AP_FILE")
        SEVERITY=$(jq -r ".[$i].severity" "$AP_FILE")

        while IFS= read -r file; do
            [ -f "$file" ] || continue
            # Check excludes
            SKIP=false
            for excl in $(jq -r ".[$i].exclude[]" "$AP_FILE" 2>/dev/null); do
                case "$file" in *$excl) SKIP=true ;; esac
            done
            [ "$SKIP" = "true" ] && continue

            if grep -nE "$PATTERN" "$file" 2>/dev/null | head -3 | grep -q .; then
                if [ "$SEVERITY" = "error" ]; then
                    echo "ERROR: $file: $MESSAGE"
                else
                    echo "WARNING: $file: $MESSAGE"
                fi
                ISSUES=$((ISSUES + 1))
            fi
        done <<< "$CHANGED_TS"
    done
else
    # Fallback to hardcoded checks if JSON not available
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        if grep -n 'console\.log' "$file" 2>/dev/null | grep -v '// eslint-disable' | grep -v 'test' >/dev/null; then
            echo "WARNING: $file: console.log found"
            ISSUES=$((ISSUES + 1))
        fi
    done <<< "$CHANGED_TS"
fi

# ── TDD Check: new source files must have tests ──
echo ""
echo "Checking TDD compliance..."

NEW_SRC_FILES="$(git diff --name-only --diff-filter=A "$BASE_REF" -- '*.ts' '*.tsx' 2>/dev/null | grep -E '^(src/|apps/)' | grep -vE '\.(test|spec|d)\.(ts|tsx)$' | grep -vE '(index\.ts|config\.ts|types\.ts|__tests__)' || echo '')"

if [ -n "$NEW_SRC_FILES" ]; then
    while IFS= read -r src_file; do
        [ -z "$src_file" ] && continue

        BASE_NAME="$(basename "$src_file" .ts)"
        BASE_NAME="$(basename "$BASE_NAME" .tsx)"
        DIR="$(dirname "$src_file")"

        TEST_EXISTS=false
        for pattern in "$DIR/$BASE_NAME.test.ts" "$DIR/$BASE_NAME.test.tsx" "$DIR/$BASE_NAME.spec.ts" "$DIR/$BASE_NAME.spec.tsx" "$DIR/__tests__/$BASE_NAME.test.ts" "$DIR/__tests__/$BASE_NAME.test.tsx"; do
            if [ -f "$pattern" ] || git diff --name-only "$BASE_REF" | grep -q "$(basename "$pattern")" 2>/dev/null; then
                TEST_EXISTS=true
                break
            fi
        done

        if [ "$TEST_EXISTS" = false ]; then
            echo "ERROR: $src_file: new source file without corresponding test"
            ISSUES=$((ISSUES + 1))
        fi
    done <<< "$NEW_SRC_FILES"
fi

if [ "$ISSUES" -gt 0 ]; then
    echo ""
    echo "Found $ISSUES potential issues."
    exit 1
fi

echo "No anti-patterns found."
