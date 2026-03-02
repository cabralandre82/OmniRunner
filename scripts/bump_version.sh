#!/usr/bin/env bash
set -euo pipefail

PUBSPEC="omni_runner/pubspec.yaml"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "Error: $PUBSPEC not found. Run from project root."
  exit 1
fi

CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3 | cut -d+ -f1)
BUILD=$(echo "$CURRENT" | cut -d+ -f2)

BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  build)
    BUILD=$((BUILD + 1))
    ;;
  *)
    echo "Usage: $0 [major|minor|patch|build]"
    exit 1
    ;;
esac

if [[ "$BUMP_TYPE" != "build" ]]; then
  BUILD=$((BUILD + 1))
fi

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${BUILD}"

sed -i "s/^version: .*/version: ${NEW_VERSION}/" "$PUBSPEC"

echo "Bumped version: $CURRENT → $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Update CHANGELOG.md with changes for v${MAJOR}.${MINOR}.${PATCH}"
echo "  2. git add -A && git commit -m 'chore: bump version to ${NEW_VERSION}'"
echo "  3. git tag v${MAJOR}.${MINOR}.${PATCH}"
