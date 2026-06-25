#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/direct"
mkdir -p "$BUILD_DIR"

"$ROOT_DIR/scripts/build_core_bridge.sh" "$BUILD_DIR" >/dev/null

swiftc \
  -enable-testing \
  -emit-library \
  -emit-module \
  -module-name JunimoCore \
  "$ROOT_DIR"/Sources/JunimoCore/*.swift \
  -L "$BUILD_DIR" \
  -ljunimo_core_bridge \
  -emit-module-path "$BUILD_DIR/JunimoCore.swiftmodule" \
  -o "$BUILD_DIR/libJunimoCore.dylib" \
  -Xlinker -install_name \
  -Xlinker "@rpath/libJunimoCore.dylib" \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

swiftc \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lJunimoCore \
  -ljunimo_core_bridge \
  "$ROOT_DIR"/Sources/Junimo/*.swift \
  -o "$BUILD_DIR/Junimo" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework UserNotifications \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

echo "$BUILD_DIR/Junimo"
