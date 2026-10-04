#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "用法：Scripts/prepare_dmg.sh <CodexUsager.app> <输出 DMG> <Developer ID Application 身份|--unsigned>" >&2
  exit 2
fi

APP="$1"
OUTPUT="$2"
IDENTITY="$3"
if [[ "$APP" != /* ]]; then APP="$PWD/$APP"; fi
if [[ "$OUTPUT" != /* ]]; then OUTPUT="$PWD/$OUTPUT"; fi

if [[ ! -d "$APP" || "$(basename "$APP")" != "CodexUsager.app" ]]; then
  echo "需要 CodexUsager.app 目录。" >&2; exit 2
fi
CHECKSUM="${OUTPUT}.sha256"
if [[ -e "$OUTPUT" || -L "$OUTPUT" || -e "$CHECKSUM" || -L "$CHECKSUM" ]]; then
  echo "输出 DMG 或校验和文件已存在，拒绝覆盖。" >&2; exit 2
fi
if [[ "$OUTPUT" != *.dmg ]]; then
  echo "输出文件必须以 .dmg 结尾。" >&2; exit 2
fi
if [[ "$IDENTITY" != --unsigned && "$IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "签名身份必须是 Developer ID Application；未签名预览须显式传入 --unsigned。" >&2; exit 2
fi
if [[ ! -d "$APP/Contents/PlugIns/CodexUsagerWidget.appex" ||
      ! -f "$APP/Contents/MacOS/ClaudeQuotaBridge" ]]; then
  echo "App 缺少 Widget 或 Claude 桥接目标。" >&2; exit 2
fi

test -x "$APP/Contents/MacOS/CodexUsager"
test -x "$APP/Contents/MacOS/ClaudeQuotaBridge"
test -x "$APP/Contents/PlugIns/CodexUsagerWidget.appex/Contents/MacOS/CodexUsagerWidget"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$APP/Contents/Info.plist")" = APPL
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = dev.codexusager.app
WIDGET_PLIST="$APP/Contents/PlugIns/CodexUsagerWidget.appex/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET_PLIST")" = dev.codexusager.app.widget
for KEY in CFBundleShortVersionString CFBundleVersion UsageAppGroup; do
  test "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$APP/Contents/Info.plist")" = "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$WIDGET_PLIST")"
done
if [[ "$IDENTITY" != --unsigned ]]; then
  codesign --verify --strict --deep --verbose=2 "$APP"
  signature=$(codesign -d --verbose=4 "$APP" 2>&1)
  if [[ "$signature" != *"Authority=$IDENTITY"* ||
        "$signature" != *"flags=0x"*"(runtime)"* ]]; then
    echo "App 必须使用 Developer ID Application 和 Hardened Runtime 签名。" >&2
    exit 2
  fi
fi

OUTPUT_DIR=$(dirname "$OUTPUT")
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "输出目录不存在。" >&2; exit 2
fi
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/codexusager-dmg.XXXXXXXX")
TEMP_DIR=""
PUBLISHED=0
cleanup() {
  status=$?
  if [[ $status -ne 0 && $PUBLISHED -eq 1 ]]; then rm -f "$OUTPUT"; fi
  rm -rf "$STAGING"
  if [[ -n "$TEMP_DIR" ]]; then rm -rf "$TEMP_DIR"; fi
}
trap cleanup EXIT
TEMP_DIR=$(mktemp -d "$OUTPUT_DIR/.codexusager-dmg.XXXXXXXX")
ditto "$APP" "$STAGING/$(basename "$APP")"
ln -s /Applications "$STAGING/Applications"
TEMP_DMG="$TEMP_DIR/CodexUsager.dmg"
hdiutil create -srcfolder "$STAGING" -volname "CodexUsager" -format UDZO "$TEMP_DMG"
if [[ "$IDENTITY" != --unsigned ]]; then
  codesign --sign "$IDENTITY" --timestamp "$TEMP_DMG"
  codesign --verify --strict --verbose=2 "$TEMP_DMG"
fi
HASH=$(shasum -a 256 "$TEMP_DMG" | awk '{print $1}')
printf '%s  %s\n' "$HASH" "$(basename "$OUTPUT")" > "$TEMP_DIR/checksum.sha256"
ln "$TEMP_DMG" "$OUTPUT"
PUBLISHED=1
ln "$TEMP_DIR/checksum.sha256" "$CHECKSUM"
echo "DMG：$OUTPUT"
echo "SHA-256：$HASH（$CHECKSUM）"
if [[ "$IDENTITY" == --unsigned ]]; then
  echo "未签名预览镜像；Gatekeeper 和 Widget 共享容器需后续运行验证。"
else
  echo "公证附票后须重新计算最终 DMG 的 SHA-256，并替换此校验和文件。"
fi
