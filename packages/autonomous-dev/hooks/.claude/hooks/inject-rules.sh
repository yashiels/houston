#!/usr/bin/env bash
# inject-rules.sh — Re-inject critical rules on session start (survives context compaction).
# Called by .claude/settings.json SessionStart hook.

# Resolve paths relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

cat << 'RULES'
+------------------------------------------------------+
|  AUTONOMOUS DEV PIPELINE — CORE RULES                |
+------------------------------------------------------+
|  1. PIPELINE REQUIRED: No edits without active state  |
|  2. TDD MANDATORY: Test before implementation         |
|  3. QUALITY GATES: Must pass before next phase        |
|  4. NO SHORTCUTS: No --no-verify, no .skip()          |
|  5. FRESH CONTEXT: Read files, don't assume           |
+------------------------------------------------------+
RULES

# Optional: Qdrant-first enforcement
# Uncomment the following to require vector search before Glob/Grep:
# echo "  6. QDRANT FIRST: Call qdrant-find before Glob/Grep"
