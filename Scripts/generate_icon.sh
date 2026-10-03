#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swift "$(dirname "$0")/icon.swift" "$TEMP/base.png"
ICONSET="$TEMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -s format png -z "$SIZE" "$SIZE" "$TEMP/base.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -s format png -z "$DOUBLE" "$DOUBLE" "$TEMP/base.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$TARGET"
