#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/ModuleCache Config/AppIcon.iconset
/usr/bin/swift -module-cache-path "$ROOT/.build/ModuleCache" scripts/draw-icon.swift Config/AppIcon-1024.png
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" Config/AppIcon-1024.png --out "Config/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  /usr/bin/sips -z "$DOUBLE" "$DOUBLE" Config/AppIcon-1024.png --out "Config/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/swift -module-cache-path "$ROOT/.build/ModuleCache" scripts/pack-icon.swift Config/AppIcon.iconset Config/AppIcon.icns
printf 'Generated Config/AppIcon.icns\n'
