#!/usr/bin/env bash
# install.sh — Install Houston as a Claude Code plugin
# Usage: ./scripts/install.sh
set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing Houston..."
echo ""

# ─── 1. Set HOUSTON_DIR in shell profile ───

SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
  if ! grep -q "HOUSTON_DIR" "$SHELL_RC" 2>/dev/null; then
    {
      echo ""
      echo "# Houston — autonomous dev orchestrator"
      echo "export HOUSTON_DIR=\"$HOUSTON_DIR\""
    } >> "$SHELL_RC"
    echo "[+] Added HOUSTON_DIR to $SHELL_RC"
  else
    # Update existing entry if path changed
    current="$(grep 'export HOUSTON_DIR=' "$SHELL_RC" | head -1 | sed 's/export HOUSTON_DIR="//' | sed 's/"$//')"
    if [ "$current" != "$HOUSTON_DIR" ]; then
      sed -i.bak "s|export HOUSTON_DIR=.*|export HOUSTON_DIR=\"$HOUSTON_DIR\"|" "$SHELL_RC"
      rm -f "${SHELL_RC}.bak"
      echo "[~] Updated HOUSTON_DIR in $SHELL_RC"
    else
      echo "[=] HOUSTON_DIR already set in $SHELL_RC"
    fi
  fi
fi

export HOUSTON_DIR="$HOUSTON_DIR"

# ─── 2. Create ~/.houston directory for runs ───

mkdir -p "$HOME/.houston/runs"
echo "[+] Created ~/.houston/runs/"

# ─── 3. Install as Claude Code plugin via marketplace ───

if command -v claude &>/dev/null; then
  echo ""
  echo "Setting up Claude Code plugin..."

  # Add marketplace (houston repo) if not already added
  if claude plugins marketplace list 2>/dev/null | grep -q "yashiels"; then
    echo "[=] Marketplace 'yashiels' already registered"
    # Update it to get latest
    claude plugins marketplace update yashiels 2>/dev/null || true
  else
    echo "[+] Adding marketplace from yashiels/houston..."
    claude plugins marketplace add yashiels/houston 2>&1 || {
      echo "[!] Failed to add marketplace. You can add it manually:"
      echo "    claude plugins marketplace add yashiels/houston"
    }
  fi

  # Install houston plugin if not already installed
  if claude plugins list 2>/dev/null | grep -q "houston@yashiels"; then
    echo "[=] Plugin houston@yashiels already installed"
    # Update it
    claude plugins update houston@yashiels 2>/dev/null || true
  else
    echo "[+] Installing houston plugin..."
    claude plugins install houston@yashiels 2>&1 || {
      echo "[!] Failed to install plugin. You can install it manually:"
      echo "    claude plugins install houston@yashiels"
    }
  fi

  echo ""
  echo "Run '/reload-plugins' in Claude Code to pick up changes."
else
  echo ""
  echo "[!] Claude Code CLI not found. Install it first, then run:"
  echo "    claude plugins marketplace add yashiels/houston"
  echo "    claude plugins install houston@yashiels"
fi

# ─── 4. Clean up old installation method ───

# Remove old skill symlink if it exists
if [ -L "$HOME/.claude/skills/houston" ]; then
  rm "$HOME/.claude/skills/houston"
  echo "[~] Removed old skill symlink"
fi

# Remove old command file if it exists
if [ -f "$HOME/.claude/commands/houston.md" ]; then
  rm "$HOME/.claude/commands/houston.md"
  echo "[~] Removed old command file"
fi

# ─── Done ───

echo ""
echo "Houston installed successfully!"
echo ""
echo "  HOUSTON_DIR:  $HOUSTON_DIR"
echo "  Plugin:       houston@yashiels"
echo "  Runs:         ~/.houston/runs/"
echo ""
echo "Usage in Claude Code:"
echo "  /houston SIP-2099              Launch pipeline for a ticket"
echo "  /houston status                Show running pipelines"
echo "  /houston resume SWITCH-167     Resume a crashed pipeline"
echo ""
echo "To update later:"
echo "  cd $HOUSTON_DIR && git pull"
echo "  claude plugins marketplace update yashiels"
echo "  claude plugins update houston@yashiels"
