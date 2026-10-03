#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "用法：Scripts/generate_icon.sh <AppIcon.icns 输出路径>" >&2
  exit 2
fi
TARGET="$1"
SOURCE="$(cd "$(dirname "$0")/.." && pwd)/Assets/AppIconSource.png"
if [[ ! -f "$SOURCE" ]]; then
  echo "缺少 App 图标源图：$SOURCE" >&2
  exit 2
fi
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
ICONSET="$TEMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -s format png -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -s format png -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$TARGET"
