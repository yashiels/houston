#!/bin/bash
# block-shortcuts.sh — Claude Code hook to block dangerous commands
# Hook type: PreToolUse
# Blocks: force push, --no-verify, ssh, docker exec, kubectl exec
set -euo pipefail

# This script receives the tool use as JSON on stdin
# It should exit 0 to allow, exit 1 to block

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only check Bash tool calls
if [ "$TOOL" != "Bash" ] || [ -z "$COMMAND" ]; then
  exit 0
fi

# Blocked patterns
BLOCKED_PATTERNS=(
  "git push.*--force"
  "git push.*-f "
  "--no-verify"
  "ssh .* "
  "docker exec"
  "kubectl exec"
  "git checkout \.\s*$"
  "git checkout -- \."
  "git reset --hard"
  "rm -rf /"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: Command matches forbidden pattern: $pattern" >&2
    echo "Houston enforces: all changes through code → test → commit → CI/CD → merge" >&2
    exit 1
  fi
done

exit 0
