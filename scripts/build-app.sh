#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm run build
if [[ ! -f Assets/AppIcon.icns || Assets/MarkUp-icon.png -nt Assets/AppIcon.icns ]]; then
  ./scripts/build-icon.sh
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/markup-clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/markup-swift-cache"
# One slice per architecture with the native build system, so each links against the current SDK
# (the multi-arch build records the deployment SDK and macOS would fall back to its legacy appearance).
for arch in arm64 x86_64; do
  swift build -c release --build-system native --disable-sandbox --triple "$arch-apple-macosx14.0"
done
APP="$PWD/dist/MarkUp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
lipo -create .build/arm64-apple-macosx/release/MarkUp .build/x86_64-apple-macosx/release/MarkUp -output "$APP/Contents/MacOS/MarkUp"
cp -R Sources/MarkUp/Resources/Web "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array><key>CFBundleExecutable</key><string>MarkUp</string><key>CFBundleIdentifier</key><string>local.markup.editor</string><key>CFBundleIconFile</key><string>AppIcon.icns</string><key>CFBundleName</key><string>MarkUp</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.4.0</string><key>CFBundleVersion</key><string>10</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Markdown</string><key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string></array><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>net.daringfireball.markdown</string></array></dict></array><key>UTImportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string><key>UTTypeDescription</key><string>Markdown</string><key>UTTypeConformsTo</key><array><string>public.plain-text</string></array><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>md</string><string>markdown</string></array><key>public.mime-type</key><string>text/markdown</string></dict></dict></array><key>UTExportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.markup.sidebar-file</string><key>UTTypeDescription</key><string>MarkUp Sidebar File</string><key>UTTypeConformsTo</key><array><string>public.data</string></array></dict></array></dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
touch "$APP"
printf 'Built %s\n' "$APP"
