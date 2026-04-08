#!/bin/bash
# update.sh — Pull latest houston and sync the Claude Code plugin
# Usage: ./scripts/update.sh
set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HOUSTON_DIR"

echo "Updating Houston..."

git pull 2>&1

VERSION="$(jq -r '.version' package.json)"

if command -v claude &>/dev/null; then
  claude plugins marketplace update yashiels 2>/dev/null || true
  claude plugins uninstall houston@yashiels 2>/dev/null || true
  claude plugins install houston@yashiels 2>&1 || {
    echo "Plugin install failed. Try: claude plugins install houston@yashiels"
    exit 1
  }
fi

echo ""
echo "Houston v${VERSION} — run '/reload-plugins' in Claude Code"
