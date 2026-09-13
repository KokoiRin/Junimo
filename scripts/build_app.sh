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
SIGNING_IDENTITY="${JUNIMO_SIGNING_IDENTITY:-}"
LOCAL_IDENTITY="$HOME/Library/Application Support/Junimo/signing/identity"
if [[ -z "$SIGNING_IDENTITY" && -f "$LOCAL_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(cat "$LOCAL_IDENTITY")"
  [[ "$SIGNING_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo "Invalid Junimo local signing identity" >&2; exit 1; }
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "warning: ad-hoc signing changes the app identity on rebuild; run scripts/setup_local_signing.sh once to preserve accessibility authorization." >&2
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"
mkdir -p "$BUILD_DIR/module-cache"

export GOCACHE="$ROOT_DIR/.build/go-build-cache"
MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  go build -o "$MACOS_DIR/junimo-backend" "$ROOT_DIR/backend/cmd/junimo-backend"

swiftc \
  -target "$SWIFT_TARGET" \
  -enable-testing \
  -emit-library \
  -emit-module \
  -module-name JunimoCore \
  "$ROOT_DIR"/Sources/JunimoShellCore/*.swift \
  -module-cache-path "$BUILD_DIR/module-cache" \
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
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR"/Sources/JunimoShell/*.swift \
  -o "$MACOS_DIR/Junimo" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
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
  <string>local.junimo.shell</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Junimo</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.2</string>
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

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ -d "$ROOT_DIR/Sources/JunimoShell/Resources" ]]; then
  cp "$ROOT_DIR"/Sources/JunimoShell/Resources/* "$RESOURCES_DIR"/
fi

find "$APP_DIR" -name '._*' -delete
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR" >&2
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null

echo "$APP_DIR"
