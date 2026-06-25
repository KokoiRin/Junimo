#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-$ROOT_DIR/.build/direct}"
mkdir -p "$BUILD_DIR"

CXX="${CXX:-clang++}"
CXXFLAGS=(
  -std=c++23
  -Wall
  -Wextra
  -Wpedantic
  -I "$ROOT_DIR/Core/include"
)

"$CXX" "${CXXFLAGS[@]}" \
  -dynamiclib \
  -install_name "@rpath/libjunimo_core_bridge.dylib" \
  "$ROOT_DIR/Core/src/models.cpp" \
  "$ROOT_DIR/Core/src/task_engine.cpp" \
  "$ROOT_DIR/Core/src/c_api.cpp" \
  -o "$BUILD_DIR/libjunimo_core_bridge.dylib"

echo "$BUILD_DIR/libjunimo_core_bridge.dylib"
