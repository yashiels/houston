#!/bin/bash
# release.sh — Bump version and create a release tag
# Usage: ./scripts/release.sh <minor|major|patch>
set -euo pipefail

HOUSTON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HOUSTON_DIR"

BUMP="${1:-}"

if [[ -z "$BUMP" || ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  echo "Usage: release.sh <patch|minor|major>" >&2
  echo "" >&2
  echo "  patch  1.1.0 → 1.1.1  (bug fixes)" >&2
  echo "  minor  1.1.0 → 1.2.0  (new features)" >&2
  echo "  major  1.1.0 → 2.0.0  (breaking changes)" >&2
  exit 1
fi

# Read current version
CURRENT="$(jq -r '.version' package.json)"
if [[ -z "$CURRENT" || "$CURRENT" == "null" ]]; then
  echo "ERROR: Cannot read current version from package.json" >&2
  exit 1
fi

# Parse semver
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEW}"

echo "Version bump: $CURRENT → $NEW ($BUMP)"
echo ""

# Check for uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Uncommitted changes. Commit or stash first." >&2
  exit 1
fi

# Check we're on master
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "master" && "$BRANCH" != "main" ]]; then
  echo "ERROR: Must be on master/main branch, currently on '$BRANCH'" >&2
  exit 1
fi

# Check tag doesn't already exist
if git tag -l "$TAG" | grep -q "$TAG"; then
  echo "ERROR: Tag $TAG already exists" >&2
  exit 1
fi

# Update version in all files
jq --arg v "$NEW" '.version = $v' package.json > tmp.json && mv tmp.json package.json
jq --arg v "$NEW" '.version = $v' .claude-plugin/plugin.json > tmp.json && mv tmp.json .claude-plugin/plugin.json
jq --arg v "$NEW" '.plugins[0].version = $v' .claude-plugin/marketplace.json > tmp.json && mv tmp.json .claude-plugin/marketplace.json

echo "Updated:"
echo "  package.json:          $NEW"
echo "  .claude-plugin/plugin: $NEW"
echo "  .claude-plugin/market: $NEW"

# Commit version bump
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to $NEW"

# Create tag
git tag -a "$TAG" -m "Houston $TAG"

echo ""
echo "Created tag: $TAG"
echo ""
echo "To publish:"
echo "  git push && git push --tags"
echo ""
echo "This will trigger the release workflow on GitHub."
