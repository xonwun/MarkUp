#!/bin/bash
# Builds MarkUp and packages it as a drag-to-install DMG and a ZIP in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/MarkUp.app/Contents/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
rm -f "dist/MarkUp-$VERSION.dmg" "dist/MarkUp-$VERSION.zip"
ditto dist/MarkUp.app "$STAGE/MarkUp.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MarkUp $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "dist/MarkUp-$VERSION.dmg"
ditto -c -k --keepParent dist/MarkUp.app "dist/MarkUp-$VERSION.zip"
printf 'Packaged dist/MarkUp-%s.dmg and dist/MarkUp-%s.zip\n' "$VERSION" "$VERSION"
