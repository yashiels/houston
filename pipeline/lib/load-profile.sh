#!/usr/bin/env bash
# load-profile.sh — Resolve and load a Houston profile for linear scripts.
# Source this file (after parse-profile.sh) and call:
#   _load_linear_context [profile_name] [houston_dir]
# Sets globals: PROFILE_JSON, LINEAR_KEY_ENV, DEFAULT_TEAM

set -euo pipefail

_load_linear_context() {
  local profile_name="${1:-}"
  local houston_dir="${2:?_load_linear_context requires houston_dir as second argument}"

  # Fall back to HOUSTON_PROFILE env var
  if [[ -z "$profile_name" && -n "${HOUSTON_PROFILE:-}" ]]; then
    profile_name="$HOUSTON_PROFILE"
  fi

  if [[ -n "$profile_name" ]]; then
    local profile_file="${houston_dir}/profiles/${profile_name}.toml"
    if [[ ! -f "$profile_file" ]]; then
      echo '{"error":"Profile not found: '"$profile_name"'"}' >&2
      return 1
    fi
    PROFILE_JSON="$(parse_profile "$profile_file")"
  else
    PROFILE_JSON="$("${houston_dir}/pipeline/detect-context.sh" "$(pwd)" "${houston_dir}/profiles" 2>/dev/null)" || {
      echo '{"error":"No profile detected — use --profile NAME or set HOUSTON_PROFILE"}' >&2
      return 1
    }
  fi

  LINEAR_KEY_ENV="$(echo "$PROFILE_JSON" | jq -r '.linear.api_key_env // "LINEAR_API_KEY"')"
  DEFAULT_TEAM="$(echo "$PROFILE_JSON" | jq -r '.linear.default_team // empty')"
}
