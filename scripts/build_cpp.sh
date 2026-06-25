#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/cpp"
mkdir -p "$BUILD_DIR"

CXX="${CXX:-clang++}"
CXXFLAGS=(
  -std=c++23
  -Wall
  -Wextra
  -Wpedantic
  -I "$ROOT_DIR/Core/include"
)

"$CXX" "${CXXFLAGS[@]}" -c "$ROOT_DIR/Core/src/models.cpp" -o "$BUILD_DIR/models.o"
"$CXX" "${CXXFLAGS[@]}" -c "$ROOT_DIR/Core/src/task_engine.cpp" -o "$BUILD_DIR/task_engine.o"
ar rcs "$BUILD_DIR/libjunimo_core.a" "$BUILD_DIR/models.o" "$BUILD_DIR/task_engine.o"

echo "$BUILD_DIR/libjunimo_core.a"
