#!/bin/zsh
# Points the Homebrew cask (xonwun/homebrew-markup) at a published release: sets its version and the .dmg's sha256.
# Run after the GitHub release is up, so `brew install` serves it. Checks the uploaded .dmg matches the local one.
# Usage: scripts/update-cask.sh [version]   (defaults to the version in dist/MarkUp.md.app)
set -euo pipefail
cd "$(dirname "$0")/.."

TAP="xonwun/homebrew-markup"
CASK="Casks/markup.rb"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/MarkUp.md.app/Contents/Info.plist)}"
DMG="dist/MarkUp.md-$VERSION.dmg"
URL="https://github.com/xonwun/MarkUp/releases/download/v$VERSION/MarkUp.md-$VERSION.dmg"

[[ -f "$DMG" ]] || { echo "Missing $DMG; run scripts/package.sh first" >&2; exit 1; }
LOCAL=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
REMOTE=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1) || { echo "No release asset at $URL; publish v$VERSION first" >&2; exit 1; }
[[ "$LOCAL" == "$REMOTE" ]] || { echo "The uploaded .dmg differs from $DMG; re-upload it before updating the cask" >&2; exit 1; }

# Read the cask through the API, so no clone is needed.
JSON=$(gh api "repos/$TAP/contents/$CASK")
FILE_SHA=$(print -r -- "$JSON" | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
OLD=$(print -r -- "$JSON" | /usr/bin/python3 -I -c 'import json,sys,base64; print(base64.b64decode(json.load(sys.stdin)["content"]).decode(), end="")')
NEW=$(print -r -- "$OLD" | sed -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$LOCAL\"/")

if [[ "$NEW" == "$OLD" ]]; then echo "Cask already at $VERSION"; exit 0; fi
gh api -X PUT "repos/$TAP/contents/$CASK" \
  -f message="Update MarkUp.md to $VERSION" \
  -f content="$(print -r -- "$NEW" | base64)" \
  -f sha="$FILE_SHA" >/dev/null
echo "Cask updated to $VERSION ($LOCAL)"
