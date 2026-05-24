#!/usr/bin/env bash
# Initialize the .autonomous-dev/ directory with state.json (v4 schema).
# Usage: init-pipeline.sh <input> [branch] [issue_id]
#
# Generalized pipeline initializer — works with any project.

set -euo pipefail

AD_STATE_DIR="${AD_STATE_DIR:-.autonomous-dev}"
PIPELINE_DIR="$AD_STATE_DIR"

INPUT="${1:?Usage: init-pipeline.sh <input> [branch] [issue_id]}"
BRANCH="${2:-$(git branch --show-current 2>/dev/null || echo "main")}"
ISSUE_ID="${3:-}"

mkdir -p "$PIPELINE_DIR"

INPUT_JSON=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > "$PIPELINE_DIR/state.json" <<EOF
{
  "version": 4,
  "pipeline": "initialized",
  "step": "tool-select",
  "input": $INPUT_JSON,
  "issue_id": "$ISSUE_ID",
  "branch": "$BRANCH",
  "tool": null,
  "mode": null,
  "preset": null,
  "models": {},
  "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastCheckpoint": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completedSteps": [],
  "currentPhase": null,
  "currentStory": null,
  "gateStatus": "running",
  "phases": {},
  "stories": {}
}
EOF

# Initialize pipeline log
mkdir -p "$PIPELINE_DIR"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] init: Pipeline initialized (input=${INPUT:0:80})" >> "$PIPELINE_DIR/.pipeline.log"

echo "Pipeline initialized at $PIPELINE_DIR"
