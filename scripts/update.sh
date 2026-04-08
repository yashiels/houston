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
echo "[*] Local version: $VERSION"

# Update Claude Code plugin
if command -v claude &>/dev/null; then
  echo "[*] Updating marketplace cache..."
  claude plugins marketplace update yashiels 2>/dev/null || true

  echo "[*] Reinstalling plugin..."
  claude plugins uninstall houston@yashiels 2>/dev/null || true
  claude plugins install houston@yashiels 2>&1 || {
    echo "[!] Plugin install failed. Try manually:"
    echo "    claude plugins install houston@yashiels"
    exit 1
  }

  # Verify sync — compare key files
  PLUGIN_PATH="$(jq -r '.plugins["houston@yashiels"][0].installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
  if [[ -n "$PLUGIN_PATH" && -d "$PLUGIN_PATH" ]]; then
    INSTALLED_VER="$(jq -r '.version' "$PLUGIN_PATH/package.json" 2>/dev/null)"
    echo "[*] Installed version: $INSTALLED_VER"

    # Check if skill file matches
    if diff -q "$HOUSTON_DIR/skills/houston.md" "$PLUGIN_PATH/skills/houston.md" >/dev/null 2>&1; then
      echo "[+] Skills: in sync"
    else
      echo "[!] Skills: OUT OF SYNC — local is newer than installed"
      echo "    This happens when local commits haven't been pushed yet."
      echo "    Push first, then run update again."
    fi

    # Check if commands match
    LOCAL_CMDS="$(ls "$HOUSTON_DIR/commands/" 2>/dev/null | wc -l | tr -d ' ')"
    INSTALLED_CMDS="$(ls "$PLUGIN_PATH/commands/" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$LOCAL_CMDS" == "$INSTALLED_CMDS" ]]; then
      echo "[+] Commands: in sync ($LOCAL_CMDS commands)"
    else
      echo "[!] Commands: OUT OF SYNC — local has $LOCAL_CMDS, installed has $INSTALLED_CMDS"
    fi

    # Check scripts
    LOCAL_SCRIPTS="$(ls "$HOUSTON_DIR/scripts/"*.sh 2>/dev/null | wc -l | tr -d ' ')"
    INSTALLED_SCRIPTS="$(ls "$PLUGIN_PATH/scripts/"*.sh 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$LOCAL_SCRIPTS" == "$INSTALLED_SCRIPTS" ]]; then
      echo "[+] Scripts: in sync ($LOCAL_SCRIPTS scripts)"
    else
      echo "[!] Scripts: OUT OF SYNC — local has $LOCAL_SCRIPTS, installed has $INSTALLED_SCRIPTS"
    fi
  fi

  echo ""
  echo "Run '/reload-plugins' in Claude Code to pick up changes."
else
  echo "[!] Claude Code CLI not found. Update the plugin manually."
fi

echo ""
echo "Houston updated to v${VERSION}"
