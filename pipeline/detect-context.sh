#!/usr/bin/env bash
# detect-context.sh — Detect which Houston profile matches a git repo's remote URL.
# Reads the repo's origin remote, normalizes it, and scans profile TOML files
# for a matching remote_patterns entry. Outputs merged JSON (profile + detected info).
#
# Usage: ./pipeline/detect-context.sh [repo-path] [profiles-dir]
#   repo-path     — path to the git repository (default: current directory)
#   profiles-dir  — path to profiles directory (default: ../profiles relative to script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the profile parser
# shellcheck source=pipeline/lib/parse-profile.sh
source "${SCRIPT_DIR}/lib/parse-profile.sh"

# --- Arguments ---
REPO_PATH="${1:-.}"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
PROFILES_DIR="${2:-${SCRIPT_DIR}/../profiles}"
PROFILES_DIR="$(cd "$PROFILES_DIR" && pwd)"

# --- Helper: emit error JSON to stderr and exit ---
emit_error() {
  local code="$1"
  shift
  echo "$@" >&2
  exit "$code"
}

# --- Step 1: Read git remote URL ---
if ! REMOTE_URL="$(git -C "$REPO_PATH" remote get-url origin 2>/dev/null)"; then
  emit_error 1 "$(cat <<EOF
{"error": "not_a_git_repo", "message": "Could not read git remote 'origin' in ${REPO_PATH}"}
EOF
)"
fi

# --- Step 2: Normalize the URL ---
# Strip protocol (https://, http://, ssh://, git://)
# Strip username@ prefix
# Strip .git suffix
# Convert : to / (for SSH-style URLs like git@github.com:org/repo)
# Lowercase everything
normalize_url() {
  local url="$1"

  # Remove protocol prefix
  url="${url#*://}"

  # Remove username@ (e.g., git@)
  url="${url#*@}"

  # Convert first colon to slash (SSH-style: github.com:org/repo -> github.com/org/repo)
  # Only if it's not already slash-separated (i.e., no / before the colon)
  if [[ "$url" == *:* && "$url" != */* ]] || [[ "$url" =~ ^[^/]+: ]]; then
    url="${url/://}"
  fi

  # Remove .git suffix
  url="${url%.git}"

  # Lowercase
  echo "$url" | tr '[:upper:]' '[:lower:]'
}

NORMALIZED="$(normalize_url "$REMOTE_URL")"

# --- Step 3: Scan profile TOML files for matching remote_patterns ---
declare -a MATCHED_PROFILES=()
declare -a MATCHED_PRIORITIES=()
declare -a MATCHED_FILES=()

for toml_file in "${PROFILES_DIR}"/*.toml; do
  [[ -f "$toml_file" ]] || continue

  # Skip schema.toml
  basename_file="$(basename "$toml_file")"
  [[ "$basename_file" == "schema.toml" ]] && continue

  # Extract profile name
  profile_name=""
  profile_priority=0

  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    if [[ "$line" =~ ^[[:space:]]*name[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      profile_name="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ ^[[:space:]]*priority[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
      profile_priority="${BASH_REMATCH[1]}"
    fi
  done < <(awk '/^\[profile\]/{found=1; next} /^\[/{found=0} found{print}' "$toml_file")

  # Extract remote_patterns array from [detect] section
  patterns_line=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*remote_patterns[[:space:]]*= ]]; then
      patterns_line="$line"
      break
    fi
  done < <(awk '/^\[detect\]/{found=1; next} /^\[/{found=0} found{print}' "$toml_file")

  [[ -z "$patterns_line" ]] && continue

  # Parse the array: extract values between quotes
  # e.g., remote_patterns = ["stitch", "exipay"]
  raw_array="${patterns_line#*=}"
  raw_array="${raw_array#"${raw_array%%[!\  ]*}"}" # trim leading whitespace

  # Extract each quoted string from the array
  matched=false
  while [[ "$raw_array" =~ \"([^\"]+)\" ]]; do
    pattern="${BASH_REMATCH[1]}"
    # Remove the matched part so we can find the next one
    raw_array="${raw_array#*"${BASH_REMATCH[0]}"}"

    # Check if pattern is a substring of the normalized URL (case-insensitive)
    pattern_lower="$(echo "$pattern" | tr '[:upper:]' '[:lower:]')"
    if [[ "$NORMALIZED" == *"$pattern_lower"* ]]; then
      matched=true
      break
    fi
  done

  if $matched; then
    MATCHED_PROFILES+=("$profile_name")
    MATCHED_PRIORITIES+=("$profile_priority")
    MATCHED_FILES+=("$toml_file")
  fi
done

# --- Step 4: Resolve matches ---
match_count="${#MATCHED_PROFILES[@]}"

if [[ "$match_count" -eq 0 ]]; then
  emit_error 1 "$(printf '{"error": "no_match", "message": "No profile matched the remote URL", "remote": "%s", "normalized": "%s"}' \
    "$REMOTE_URL" "$NORMALIZED")"
fi

# Find the highest priority
best_idx=0
best_priority="${MATCHED_PRIORITIES[0]}"

for ((i = 1; i < match_count; i++)); do
  if [[ "${MATCHED_PRIORITIES[$i]}" -gt "$best_priority" ]]; then
    best_priority="${MATCHED_PRIORITIES[$i]}"
    best_idx=$i
  fi
done

# Check for ties at the highest priority
tied_names=()
for ((i = 0; i < match_count; i++)); do
  if [[ "${MATCHED_PRIORITIES[$i]}" -eq "$best_priority" ]]; then
    tied_names+=("${MATCHED_PROFILES[$i]}")
  fi
done

if [[ "${#tied_names[@]}" -gt 1 ]]; then
  # Build JSON array of tied profile names
  names_json="$(printf '"%s",' "${tied_names[@]}")"
  names_json="[${names_json%,}]"
  emit_error 2 "$(printf '{"error": "ambiguous", "message": "Multiple profiles matched with same priority (%s)", "matches": %s}' \
    "$best_priority" "$names_json")"
fi

WINNING_FILE="${MATCHED_FILES[$best_idx]}"

# --- Step 5: Detect platform ---
if [[ "$NORMALIZED" == *github* ]]; then
  PLATFORM="github"
  CLI="gh"
elif [[ "$NORMALIZED" == *gitlab* ]]; then
  PLATFORM="gitlab"
  CLI="glab"
else
  PLATFORM="unknown"
  CLI=""
fi

# --- Step 6: Parse the winning profile and merge with detected info ---
PROFILE_JSON="$(parse_profile "$WINNING_FILE")"

DETECTED_JSON="$(cat <<EOF
{
  "detected": {
    "platform": "${PLATFORM}",
    "cli": "${CLI}",
    "remote": "${REMOTE_URL}",
    "normalized": "${NORMALIZED}",
    "repo_path": "${REPO_PATH}"
  }
}
EOF
)"

# Merge profile JSON with detected info using jq
echo "$PROFILE_JSON" | jq --argjson detected "$DETECTED_JSON" '. + $detected'
