#!/usr/bin/env bash
# shellcheck disable=SC2034  # All vars are sourced by ac.sh, not used directly
# autonomous-dev configuration
# Copy to your project root as .autonomous-dev.conf
#
# Usage:
#   cp /path/to/autonomous-dev/config.example.sh /path/to/project/.autonomous-dev.conf
#   # Edit values, then run:
#   /path/to/autonomous-dev/ac.sh /path/to/project

# ── LLM Configuration ──────────────────────────────────────────────────────

# LLM CLI to use (claude, opencode, gemini, aider)
AD_LLM_CLI="claude"

# Default mode (supervised, autonomous, human-assisted)
AD_DEFAULT_MODE="supervised"

# Default model preset (budget, balanced, premium, custom)
AD_DEFAULT_PRESET="balanced"

# ── Git / PR Configuration ──────────────────────────────────────────────────

# Co-author for git commits
AD_CO_AUTHOR="Your Name <your@email.com>"

# PR reviewers (comma-separated GitHub usernames)
AD_REVIEWERS=""

# Base branch for PRs (default: main)
# AD_BASE_BRANCH="main"

# ── Vector Indexer (Optional) ───────────────────────────────────────────────

# Qdrant URL for vector indexer
AD_QDRANT_URL="http://localhost:6333"

# ── Custom Commands (Override Auto-Detection) ───────────────────────────────
# Uncomment and set these to override the auto-detected commands for your stack.

# Custom test command
# AD_TEST_CMD=""

# Custom build command
# AD_BUILD_CMD=""

# Custom typecheck command
# AD_TYPECHECK_CMD=""

# Custom lint command
# AD_LINT_CMD=""

# ── Timeouts ────────────────────────────────────────────────────────────────
# Override default agent timeouts (in seconds)

# AD_TIMEOUT_RESEARCHER=1800
# AD_TIMEOUT_PLANNER=1800
# AD_TIMEOUT_PHASE_SUPERVISOR=7200
# AD_TIMEOUT_TESTER=1800
# AD_TIMEOUT_FINAL_REVIEWER=2700
# AD_TIMEOUT_CI_MONITOR=3600
