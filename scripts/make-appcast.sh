#!/bin/bash
# Writes dist/appcast.xml, the feed installed copies read (SUFeedURL in build-app.sh) to find updates.
# Signs the release .zip with the Sparkle EdDSA private key in the login keychain (made once by Sparkle's generate_keys;
# its public half is SUPublicEDKey in build-app.sh). Upload dist/appcast.xml to the GitHub release beside the .dmg and .zip.
# Usage: scripts/make-appcast.sh [version]   (defaults to the version in dist/MarkUp.md.app)
set -euo pipefail
cd "$(dirname "$0")/.."
INFO=dist/MarkUp.md.app/Contents/Info.plist
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO")}"
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO")
MINIMUM=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$INFO")
ZIP="dist/MarkUp.md-$VERSION.zip"
SIGN=.build/artifacts/sparkle/Sparkle/bin/sign_update
[[ -f "$ZIP" ]] || { echo "Missing $ZIP; run scripts/package.sh first" >&2; exit 1; }
[[ -x "$SIGN" ]] || { echo "Missing $SIGN; run swift package resolve first" >&2; exit 1; }
# Sparkle compares CFBundleVersion, so every release needs a larger one than the last.
PREVIOUS=$(curl -fsSL "https://github.com/xonwun/MarkUp/releases/latest/download/appcast.xml" 2>/dev/null | sed -n 's/.*<sparkle:version>\(.*\)<\/sparkle:version>.*/\1/p' | head -1 || true)
if [[ -n "$PREVIOUS" && "$BUILD" -le "$PREVIOUS" ]]; then echo "CFBundleVersion $BUILD is not above the published $PREVIOUS; bump it in build-app.sh" >&2; exit 1; fi

SIGNATURE=$("$SIGN" "$ZIP")   # sparkle:edSignature="…" length="…"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
TAG="https://github.com/xonwun/MarkUp/releases/tag/v$VERSION"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MarkUp.md</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$TAG</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/xonwun/MarkUp/releases/download/v$VERSION/MarkUp.md-$VERSION.zip" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML
echo "Wrote dist/appcast.xml for $VERSION (build $BUILD)"
