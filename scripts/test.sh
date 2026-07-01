#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/direct"
mkdir -p "$BUILD_DIR"
CORNER_NOTE_CACHE_PATH="$BUILD_DIR/corner-note-test.cache"
rm -f "$CORNER_NOTE_CACHE_PATH"

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
  "$ROOT_DIR"/Tests/JunimoDirectTests/main.swift \
  -o "$BUILD_DIR/JunimoCoreSmokeTests" \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

JUNIMO_CORNER_NOTE_CACHE_PATH="$CORNER_NOTE_CACHE_PATH" \
"$BUILD_DIR/JunimoCoreSmokeTests"

swiftc \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lJunimoCore \
  -ljunimo_core_bridge \
  "$ROOT_DIR"/Sources/Junimo/ReminderDelivery.swift \
  "$ROOT_DIR"/Sources/Junimo/LaunchLifecycleDiagnostics.swift \
  "$ROOT_DIR"/Sources/Junimo/CodexMonitorRefreshBridge.swift \
  "$ROOT_DIR"/Sources/Junimo/LaunchHealthReporter.swift \
  "$ROOT_DIR"/Sources/Junimo/JunimoRuntime.swift \
  "$ROOT_DIR"/Sources/Junimo/JunimoSurfaceView.swift \
  "$ROOT_DIR"/Tests/JunimoAppDirectTests/main.swift \
  -o "$BUILD_DIR/JunimoAppSmokeTests" \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

JUNIMO_CORNER_NOTE_CACHE_PATH="$CORNER_NOTE_CACHE_PATH" \
"$BUILD_DIR/JunimoAppSmokeTests"
