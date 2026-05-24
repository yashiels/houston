#!/usr/bin/env bash
# Setup script for the Qdrant vector indexer.
# Installs dependencies, starts Qdrant, and runs initial index.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"

echo "=== autonomous-dev: Qdrant Indexer Setup ==="
echo ""

# ── 1. Check Docker ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed or not in PATH."
    echo ""
    echo "Install Docker:"
    echo "  macOS:  brew install --cask docker"
    echo "  Linux:  https://docs.docker.com/engine/install/"
    echo "  Or use Rancher Desktop / OrbStack / Colima"
    echo ""
    echo "After installing, run this script again."
    exit 1
fi

echo "[1/5] Docker found: $(docker --version)"

# ── 2. Start Qdrant container ───────────────────────────────────────────────
if docker ps --filter "name=qdrant" --format "{{.Names}}" 2>/dev/null | grep -q qdrant; then
    echo "[2/5] Qdrant container already running"
else
    echo "[2/5] Starting Qdrant container..."
    if docker ps -a --filter "name=qdrant" --format "{{.Names}}" 2>/dev/null | grep -q qdrant; then
        docker start qdrant >/dev/null
    else
        docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant:latest >/dev/null
    fi

    # Wait for healthy
    echo "  Waiting for Qdrant to be ready..."
    # shellcheck disable=SC2034
    for _i in $(seq 1 15); do
        if curl -sf "http://localhost:6333/healthz" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if ! curl -sf "http://localhost:6333/healthz" >/dev/null 2>&1; then
        echo "ERROR: Qdrant failed to start. Check: docker logs qdrant"
        exit 1
    fi
    echo "  Qdrant ready at http://localhost:6333"
fi

# ── 3. Create Python venv ───────────────────────────────────────────────────
VENV_DIR="$SCRIPT_DIR/.venv"
if [ -d "$VENV_DIR" ]; then
    echo "[3/5] Python venv already exists at $VENV_DIR"
else
    echo "[3/5] Creating Python venv..."
    python3 -m venv "$VENV_DIR"
fi

# ── 4. Install requirements ─────────────────────────────────────────────────
echo "[4/5] Installing Python dependencies..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install -q -r "$SCRIPT_DIR/requirements.txt"

# ── 5. Run initial full index ────────────────────────────────────────────────
echo "[5/5] Running initial full index of $PROJECT_DIR..."
python3 "$SCRIPT_DIR/index_codebase.py" --workspace "$PROJECT_DIR" --full

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  - To reindex incrementally:  $SCRIPT_DIR/session-reindex.sh --project-dir $PROJECT_DIR"
echo "  - To hook into Claude Code session start, add to .claude/hooks.json:"
echo '    { "hooks": { "SessionStart": [{ "command": "'$SCRIPT_DIR'/session-reindex.sh" }] } }'
echo "  - To do a clean rebuild:     source $VENV_DIR/bin/activate && python3 $SCRIPT_DIR/index_codebase.py --workspace $PROJECT_DIR --clean"
