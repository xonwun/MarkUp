#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/MarkUp-icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Assets/MarkUp-icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o Assets/AppIcon.icns
