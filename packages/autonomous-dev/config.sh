#!/usr/bin/env bash
# shellcheck disable=SC2034
# autonomous-dev global config — Apex/Tashmia setup
# GLM is the OpenClaw agent model, but autonomous-dev uses Claude Code

# Use Claude Code as the LLM CLI
AD_LLM_CLI="claude"

# Co-author for commits (never use AI co-author)
AD_CO_AUTHOR="Yashiel Sookdeo <yashiel@skyner.co.za>"

# PR reviewers
AD_REVIEWERS="yashielsookdeo,MphoCodes"

# GitHub Actions runner label — NEVER use ubuntu-latest
AD_RUNNER_LABEL='[self-hosted, Linux, X64, astra]'

# Note: Mode and preset are NOT configured here.
# The pipeline always asks the user to select mode (supervised/autonomous/human-assisted)
# and preset (budget/balanced/premium/custom) at startup.
