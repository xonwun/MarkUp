#!/bin/bash
# Builds MarkUp.md and packages it as a drag-to-install DMG and a ZIP in dist/.
# The DMG opens to a guided window: the app, an arrow, and the Applications folder (background drawn by
# make-dmg-background.swift). The window layout is saved by Finder, so this needs a logged-in Mac session.
set -euo pipefail
cd "$(dirname "$0")/.."
MARKUP_RELEASE=1 ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/MarkUp.md.app/Contents/Info.plist)
VOLUME="MarkUp.md $VERSION"
DMG="dist/MarkUp.md-$VERSION.dmg"
WORK=$(mktemp -d)
MOUNT="/Volumes/$VOLUME"
cleanup() { hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
rm -f "$DMG" "dist/MarkUp.md-$VERSION.zip"

# Stage the app, the Applications shortcut, and the hidden background folder.
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto dist/MarkUp.md.app "$STAGE/MarkUp.md.app"
ln -s /Applications "$STAGE/Applications"
swift scripts/make-dmg-background.swift "$WORK/background" >/dev/null
# One multi-resolution image, so the background stays sharp on Retina displays.
tiffutil -cathidpicheck "$WORK/background/background.png" "$WORK/background/background@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

# Writable image first, so Finder can store the window's size, icon positions, and background.
[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov -quiet "$WORK/rw.dmg"
hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen -quiet

# 612×416 content plus the title bar. Icon positions sit in the stage of the background image.
osascript <<OSA
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 812, 564}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "MarkUp.md.app" of container window to {170, 160}
    set position of item "Applications" of container window to {442, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
# Finder writes .DS_Store a moment after the window closes.
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f "$MOUNT/.DS_Store" ]] && break; sleep 1; done
[[ -f "$MOUNT/.DS_Store" ]] || { echo "Finder did not save the DMG window layout" >&2; exit 1; }
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet

ditto -c -k --keepParent dist/MarkUp.md.app "dist/MarkUp.md-$VERSION.zip"
printf 'Packaged %s and dist/MarkUp.md-%s.zip\n' "$DMG" "$VERSION"
