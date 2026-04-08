#!/bin/bash
# install.sh — Install Houston as a Claude Code skill
# Usage: ./scripts/install.sh
set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing Houston..."

# Create global skill link
SKILL_DIR="$HOME/.claude/skills"
mkdir -p "$SKILL_DIR"

# Link Houston skills directory
if [ -L "$SKILL_DIR/houston" ]; then
  rm "$SKILL_DIR/houston"
fi
ln -sf "$HOUSTON_DIR/skills" "$SKILL_DIR/houston"

# Set HOUSTON_DIR in shell profile if not already set
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
  if ! grep -q "HOUSTON_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Houston — autonomous dev orchestrator" >> "$SHELL_RC"
    echo "export HOUSTON_DIR=\"$HOUSTON_DIR\"" >> "$SHELL_RC"
    echo "Added HOUSTON_DIR to $SHELL_RC"
  else
    echo "HOUSTON_DIR already in $SHELL_RC"
  fi
fi

# Create ~/.houston directory for runs
mkdir -p "$HOME/.houston/runs"

echo ""
echo "Houston installed successfully!"
echo "  HOUSTON_DIR: $HOUSTON_DIR"
echo "  Skills:      $SKILL_DIR/houston"
echo "  Runs:        ~/.houston/runs/"
echo ""
echo "Restart your shell or run: export HOUSTON_DIR=\"$HOUSTON_DIR\""
echo "Then use: /houston <TICKET-ID> in Claude Code"
