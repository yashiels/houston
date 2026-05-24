#!/usr/bin/env bash
# Session startup script: ensure Qdrant is running and reindex changed files.
# Called by .claude/hooks.json on SessionStart or .githooks/post-checkout.
#
# Usage:
#   session-reindex.sh                         # Index current directory
#   session-reindex.sh --project-dir /path     # Index specific directory
#
# Environment:
#   AD_QDRANT_URL   Qdrant endpoint (default: http://localhost:6333)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"
QDRANT_URL="${AD_QDRANT_URL:-http://localhost:6333}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# ── 1. Ensure Qdrant container is running ───────────────────────────────────
if command -v docker &>/dev/null; then
    if ! docker ps --filter "name=qdrant" --format "{{.Names}}" 2>/dev/null | grep -q qdrant; then
        docker start qdrant >/dev/null 2>&1 || true
        sleep 2
    fi
fi

# ── 2. Wait for Qdrant to be healthy (up to 15s) ────────────────────────────
# shellcheck disable=SC2034
for _i in $(seq 1 15); do
    if curl -sf "$QDRANT_URL/healthz" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! curl -sf "$QDRANT_URL/healthz" >/dev/null 2>&1; then
    echo "Warning: Qdrant not reachable at $QDRANT_URL"
    exit 0  # don't block session start
fi

# ── 3. Run incremental reindex ───────────────────────────────────────────────
if [ -d "$SCRIPT_DIR/.venv" ]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/.venv/bin/activate"
    python3 "$SCRIPT_DIR/index_codebase.py" --workspace "$PROJECT_DIR" --incremental 2>&1
else
    echo "Warning: Python venv not found at $SCRIPT_DIR/.venv — run indexer/setup.sh first"
fi
