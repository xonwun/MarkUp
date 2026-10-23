#!/bin/bash
# Builds Assets/AppIcon.icns (release) and Assets/AppIcon-dev.icns (development, blue emblem) from their masters.
set -euo pipefail
cd "$(dirname "$0")/.."
build() {
  local master="$1" icns="$2" set=".build/$(basename "$2" .icns).iconset"
  mkdir -p "$set"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$master" --out "$set/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$master" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$icns"
}
build Assets/MarkUp-icon.png Assets/AppIcon.icns
# The dev master is the release master with its teal emblem turned blue.
swift scripts/make-dev-icon.swift Assets/MarkUp-icon.png Assets/MarkUp-icon-dev.png
build Assets/MarkUp-icon-dev.png Assets/AppIcon-dev.icns
