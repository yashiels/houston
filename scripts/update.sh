#!/bin/bash
# update.sh — Pull latest houston and sync the Claude Code plugin
# Usage: ./scripts/update.sh
set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HOUSTON_DIR"

echo "Updating Houston..."

# Pull latest
echo "[*] Pulling latest..."
git pull 2>&1

VERSION="$(jq -r '.version' package.json)"
echo "[*] Version: $VERSION"

# Update Claude Code plugin
if command -v claude &>/dev/null; then
  echo "[*] Syncing Claude Code plugin..."
  claude plugins marketplace update yashiels 2>/dev/null || true
  claude plugins uninstall houston@yashiels 2>/dev/null || true
  claude plugins install houston@yashiels 2>&1 || {
    echo "[!] Plugin install failed. Try manually:"
    echo "    claude plugins install houston@yashiels"
  }
  echo ""
  echo "Run '/reload-plugins' in Claude Code to pick up changes."
else
  echo "[!] Claude Code CLI not found. Update the plugin manually."
fi

echo ""
echo "Houston updated to v${VERSION}"
