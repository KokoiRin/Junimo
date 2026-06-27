#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/verify_ci.sh"
"$ROOT_DIR/scripts/verify_launch_health.sh" >/dev/null
"$ROOT_DIR/scripts/verify_functional_scenario.sh" >/dev/null
openspec validate --all --strict
git diff --check

echo "Junimo verification passed"
