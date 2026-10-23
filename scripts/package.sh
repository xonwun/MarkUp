#!/bin/bash
# Builds MarkUp.md and packages it as a drag-to-install DMG and a ZIP in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
MARKUP_RELEASE=1 ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/MarkUp.md.app/Contents/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
rm -f "dist/MarkUp.md-$VERSION.dmg" "dist/MarkUp.md-$VERSION.zip"
ditto dist/MarkUp.md.app "$STAGE/MarkUp.md.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MarkUp.md $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "dist/MarkUp.md-$VERSION.dmg"
ditto -c -k --keepParent dist/MarkUp.md.app "dist/MarkUp.md-$VERSION.zip"
printf 'Packaged dist/MarkUp.md-%s.dmg and dist/MarkUp.md-%s.zip\n' "$VERSION" "$VERSION"
