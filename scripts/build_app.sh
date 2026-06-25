#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/app/Junimo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/.build/app-build"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

"$ROOT_DIR/scripts/build_core_bridge.sh" "$FRAMEWORKS_DIR" >/dev/null

swiftc \
  -enable-testing \
  -emit-library \
  -emit-module \
  -module-name JunimoCore \
  "$ROOT_DIR"/Sources/JunimoCore/*.swift \
  -L "$FRAMEWORKS_DIR" \
  -ljunimo_core_bridge \
  -emit-module-path "$BUILD_DIR/JunimoCore.swiftmodule" \
  -o "$FRAMEWORKS_DIR/libJunimoCore.dylib" \
  -Xlinker -rpath \
  -Xlinker "@loader_path"

swiftc \
  -I "$BUILD_DIR" \
  -L "$FRAMEWORKS_DIR" \
  -lJunimoCore \
  -ljunimo_core_bridge \
  "$ROOT_DIR"/Sources/Junimo/*.swift \
  -o "$MACOS_DIR/Junimo" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework UserNotifications \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Junimo</string>
  <key>CFBundleIdentifier</key>
  <string>local.junimo.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Junimo</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
