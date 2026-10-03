#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
ARCHES=("$(uname -m)")
if [[ "${2:-}" == "--universal" ]]; then ARCHES=(arm64 x86_64); fi
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  echo "Usage: Scripts/package_app.sh [debug|release] [--universal]" >&2; exit 2
fi
cd "$ROOT"
for ARCH in "${ARCHES[@]}"; do
  swift build --configuration "$CONFIG" --triple "${ARCH}-apple-macosx14.6" --product CodexUsager
  swift build --configuration "$CONFIG" --triple "${ARCH}-apple-macosx14.6" --product ClaudeQuotaBridge
done
APP="$ROOT/build/CodexUsager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#ARCHES[@]} -eq 2 ]]; then
  lipo -create "$ROOT/.build/arm64-apple-macosx/$CONFIG/CodexUsager" "$ROOT/.build/x86_64-apple-macosx/$CONFIG/CodexUsager" -output "$APP/Contents/MacOS/CodexUsager"
  lipo -create "$ROOT/.build/arm64-apple-macosx/$CONFIG/ClaudeQuotaBridge" "$ROOT/.build/x86_64-apple-macosx/$CONFIG/ClaudeQuotaBridge" -output "$APP/Contents/MacOS/ClaudeQuotaBridge"
else
  cp "$ROOT/.build/${ARCHES[0]}-apple-macosx/$CONFIG/CodexUsager" "$APP/Contents/MacOS/CodexUsager"
  cp "$ROOT/.build/${ARCHES[0]}-apple-macosx/$CONFIG/ClaudeQuotaBridge" "$APP/Contents/MacOS/ClaudeQuotaBridge"
fi
chmod +x "$APP/Contents/MacOS/CodexUsager" "$APP/Contents/MacOS/ClaudeQuotaBridge"
cp -R "$ROOT/.build/${ARCHES[0]}-apple-macosx/$CONFIG/CodexUsager_CodexUsager.bundle" "$APP/Contents/Resources/"
xcrun xcstringstool compile "$ROOT/Sources/CodexUsager/Resources/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"
"$ROOT/Scripts/generate_icon.sh" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CodexUsager</string>
<key>CFBundleDisplayName</key><string>CodexUsager</string>
<key>CFBundleIdentifier</key><string>dev.codexusager.app</string>
<key>CFBundleExecutable</key><string>CodexUsager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>14.6</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
lipo -archs "$APP/Contents/MacOS/CodexUsager"
echo "$APP"
