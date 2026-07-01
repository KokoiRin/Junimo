#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/app/Junimo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/.build/app-build"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
SWIFT_TARGET="${SWIFT_TARGET:-arm64-apple-macosx${DEPLOYMENT_TARGET}}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" "$ROOT_DIR/scripts/build_core_bridge.sh" "$FRAMEWORKS_DIR" >/dev/null

swiftc \
  -target "$SWIFT_TARGET" \
  -enable-testing \
  -emit-library \
  -emit-module \
  -module-name JunimoCore \
  "$ROOT_DIR"/Sources/JunimoCore/*.swift \
  -L "$FRAMEWORKS_DIR" \
  -ljunimo_core_bridge \
  -emit-module-path "$BUILD_DIR/JunimoCore.swiftmodule" \
  -o "$FRAMEWORKS_DIR/libJunimoCore.dylib" \
  -Xlinker -install_name \
  -Xlinker "@rpath/libJunimoCore.dylib" \
  -Xlinker -rpath \
  -Xlinker "@loader_path"

swiftc \
  -target "$SWIFT_TARGET" \
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

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
  <string>0.1.12</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>${DEPLOYMENT_TARGET}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -d "$ROOT_DIR/Sources/Junimo/Resources" ]]; then
  cp "$ROOT_DIR"/Sources/Junimo/Resources/* "$RESOURCES_DIR"/
fi

echo "$APP_DIR"
