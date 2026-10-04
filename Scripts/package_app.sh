#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
if [[ $# -gt 0 ]]; then shift; fi
case "$CONFIG" in
  debug) CONFIG=Debug ;;
  release) CONFIG=Release ;;
  *) echo "用法：Scripts/package_app.sh [debug|release] [--universal] [--unsigned] [--team TEAM_ID] [--output CodexUsager.app]" >&2; exit 2 ;;
esac
UNIVERSAL=0
UNSIGNED=0
TEAM=""
APP="$ROOT/build/CodexUsager.app"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) UNIVERSAL=1; shift ;;
    --unsigned) UNSIGNED=1; shift ;;
    --team|--output)
      if [[ $# -lt 2 || -z "$2" ]]; then echo "$1 缺少参数。" >&2; exit 2; fi
      if [[ "$1" == --team ]]; then TEAM="$2"; else APP="$2"; fi
      shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
if [[ "$APP" != /* ]]; then APP="$PWD/$APP"; fi
if [[ "$(basename "$APP")" != CodexUsager.app || -e "$APP" || -L "$APP" ]]; then
  echo "输出必须是尚不存在的 CodexUsager.app，拒绝覆盖。" >&2; exit 2
fi
mkdir -p "$(dirname "$APP")"
APP="$(cd "$(dirname "$APP")" && pwd)/CodexUsager.app"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/codexusager-build.XXXXXXXX")
STAGING=""
cleanup() {
  rm -rf "$WORK"
  if [[ -n "$STAGING" ]]; then rm -rf "$STAGING"; fi
}
trap cleanup EXIT
ARGS=(-project "$ROOT/CodexUsager.xcodeproj" -scheme CodexUsager -configuration "$CONFIG"
      -destination 'generic/platform=macOS' -derivedDataPath "$WORK/DerivedData")
if [[ $UNIVERSAL -eq 1 ]]; then ARGS+=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO); fi
if [[ -n "$TEAM" ]]; then ARGS+=("DEVELOPMENT_TEAM=$TEAM"); fi
# Explicit unsigned artifacts retain the project's entitlements and capabilities.
if [[ $UNSIGNED -eq 1 ]]; then ARGS+=(CODE_SIGNING_ALLOWED=NO); fi
xcodebuild "${ARGS[@]}" build

PRODUCT="$WORK/DerivedData/Build/Products/$CONFIG/CodexUsager.app"
WIDGET="$PRODUCT/Contents/PlugIns/CodexUsagerWidget.appex"
PLIST="$PRODUCT/Contents/Info.plist"
WIDGET_PLIST="$WIDGET/Contents/Info.plist"
test -d "$PRODUCT"
test -d "$WIDGET"
test -s "$PRODUCT/Contents/Resources/AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" = APPL
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = dev.codexusager.app
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET_PLIST")" = dev.codexusager.app.widget
for KEY in CFBundleShortVersionString CFBundleVersion UsageAppGroup; do
  test "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST")" = "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$WIDGET_PLIST")"
done
for BINARY in "$PRODUCT/Contents/MacOS/CodexUsager" "$WIDGET/Contents/MacOS/CodexUsagerWidget" "$PRODUCT/Contents/MacOS/ClaudeQuotaBridge"; do
  test -x "$BINARY"
  if [[ $UNIVERSAL -eq 1 ]]; then lipo "$BINARY" -verify_arch arm64 x86_64; fi
done
if [[ $UNSIGNED -eq 0 ]]; then codesign --verify --strict --deep "$PRODUCT"; fi
STAGING=$(mktemp -d "$(dirname "$APP")/.codexusager-app.XXXXXXXX")
ditto "$PRODUCT" "$STAGING/CodexUsager.app"
# Target the parent so an existing App directory is not treated as a container.
mv -n "$STAGING/CodexUsager.app" "$(dirname "$APP")/"
if [[ -e "$STAGING/CodexUsager.app" ]]; then echo "输出已存在，拒绝覆盖。" >&2; exit 2; fi
if [[ $UNSIGNED -eq 1 ]]; then
  echo "未签名构建；Gatekeeper 和 Widget 的 App Group 运行能力尚未验证。" >&2
fi
echo "$APP"
