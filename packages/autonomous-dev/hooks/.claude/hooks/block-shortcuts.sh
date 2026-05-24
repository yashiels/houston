#!/usr/bin/env bash
# block-shortcuts.sh — Block dangerous shortcut commands
# Called by .claude/settings.json PreToolUse hook.
#
# Environment (set by Claude Code):
#   CLAUDE_TOOL_NAME  — the tool being invoked
#   CLAUDE_TOOL_INPUT — JSON string with tool parameters
#
# Exit codes:
#   0 — allow the tool call
#   2 — block with message on stdout

set -euo pipefail

TOOL="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

# Only check Bash tool calls
if [[ "$TOOL" != "Bash" ]]; then
  exit 0
fi

# Extract command from tool input
CMD=""
if [ -n "$TOOL_INPUT" ]; then
  CMD=$(echo "$TOOL_INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('command', ''))
except:
    print('')
" 2>/dev/null || echo "")
fi

[ -z "$CMD" ] && exit 0

# Block SSH into servers
if echo "$CMD" | grep -qE '^\s*ssh\s'; then
  echo "BLOCK: SSH into servers is forbidden. All changes must go through code -> commit -> CI/CD."
  echo "  See: rules/no-shortcuts.md"
  exit 2
fi

# Block docker exec (interactive container access)
if echo "$CMD" | grep -qE 'docker\s+exec\s'; then
  echo "BLOCK: docker exec is forbidden. Fix issues in source code, not inside containers."
  echo "  See: rules/no-shortcuts.md"
  exit 2
fi

# Block kubectl exec (interactive pod access)
if echo "$CMD" | grep -qE 'kubectl\s+exec\s'; then
  echo "BLOCK: kubectl exec is forbidden. Fix issues in source code, not inside pods."
  echo "  See: rules/no-shortcuts.md"
  exit 2
fi

# Block force push
if echo "$CMD" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+-f\s'; then
  echo "BLOCK: Force push is forbidden. It rewrites shared history and can destroy work."
  echo "  Use: git push (without --force)"
  exit 2
fi

# Block skip CI
if echo "$CMD" | grep -qE '\[skip ci\]|\[ci skip\]|--no-verify'; then
  echo "BLOCK: Skipping CI/hooks is forbidden. All changes must pass CI."
  echo "  See: rules/no-shortcuts.md"
  exit 2
fi

# Block --no-verify on git commands
if echo "$CMD" | grep -qE 'git\s+(commit|push)\s+.*--no-verify'; then
  echo "BLOCK: --no-verify is forbidden. Git hooks exist for a reason."
  echo "  See: rules/no-shortcuts.md"
  exit 2
fi

exit 0
