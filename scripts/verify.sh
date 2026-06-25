#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/test_cpp.sh"
"$ROOT_DIR/scripts/build_core_bridge.sh" "$ROOT_DIR/.build/direct" >/dev/null
"$ROOT_DIR/scripts/build.sh" >/dev/null
"$ROOT_DIR/scripts/build_app.sh" >/dev/null
"$ROOT_DIR/scripts/verify_launch_health.sh" >/dev/null
"$ROOT_DIR/scripts/verify_functional_scenario.sh" >/dev/null
openspec validate bootstrap-hover-console --strict
openspec validate add-cpp23-core-framework --strict
openspec validate bridge-swift-to-cpp-core --strict
openspec validate add-command-palette-profiles --strict
openspec validate add-session-timeline --strict
openspec validate add-ui-preferences-core --strict
openspec validate add-launch-health-snapshot --strict
openspec validate add-notch-anchor-and-quit --strict
git diff --check

echo "Junimo verification passed"
