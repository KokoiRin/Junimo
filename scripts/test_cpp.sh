#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/cpp"
LIB_PATH="$("$ROOT_DIR/scripts/build_cpp.sh")"

CXX="${CXX:-clang++}"
CXXFLAGS=(
  -std=c++23
  -Wall
  -Wextra
  -Wpedantic
  -I "$ROOT_DIR/Core/include"
)

"$CXX" "${CXXFLAGS[@]}" "$ROOT_DIR/Core/tests/core_smoke_test.cpp" "$LIB_PATH" -o "$BUILD_DIR/core_smoke_test"
"$BUILD_DIR/core_smoke_test"
