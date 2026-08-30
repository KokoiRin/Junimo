#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/direct"
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/module-cache"
export GOCACHE="$BUILD_DIR/go-build-cache"

go test "$ROOT_DIR/backend/..."
go build -o "$BUILD_DIR/junimo-backend" "$ROOT_DIR/backend/cmd/junimo-backend"

swiftc \
  -enable-testing \
  -emit-library \
  -emit-module \
  -module-name JunimoCore \
  "$ROOT_DIR"/Sources/JunimoShellCore/*.swift \
  -module-cache-path "$BUILD_DIR/module-cache" \
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
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR"/Tests/JunimoDirectTests/main.swift \
  -o "$BUILD_DIR/JunimoCoreSmokeTests" \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

"$BUILD_DIR/JunimoCoreSmokeTests"

swiftc \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lJunimoCore \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR"/Tests/JunimoStateTests/main.swift \
  -o "$BUILD_DIR/JunimoStateTests" \
  -framework Combine \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

"$BUILD_DIR/JunimoStateTests"

swiftc \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lJunimoCore \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR"/Tests/JunimoBackendContractTests/main.swift \
  -o "$BUILD_DIR/JunimoBackendContractTests" \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

"$BUILD_DIR/JunimoBackendContractTests" "$BUILD_DIR/junimo-backend"

swiftc \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lJunimoCore \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR"/Sources/JunimoShell/JunimoDesignSystem.swift \
  "$ROOT_DIR"/Sources/JunimoShell/MacQuickLaunchWorkspace.swift \
  "$ROOT_DIR"/Sources/JunimoShell/JunimoSurfaceView.swift \
  "$ROOT_DIR"/Tests/JunimoVisualTests/main.swift \
  -o "$BUILD_DIR/JunimoVisualTests" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR"

"$BUILD_DIR/JunimoVisualTests"

echo "Junimo shell smoke tests passed"
