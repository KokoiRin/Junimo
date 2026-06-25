#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/test_cpp.sh"
"$ROOT_DIR/scripts/build_core_bridge.sh" "$ROOT_DIR/.build/direct" >/dev/null
"$ROOT_DIR/scripts/build.sh" >/dev/null
"$ROOT_DIR/scripts/build_app.sh" >/dev/null
git diff --check

echo "Junimo CI verification passed"
