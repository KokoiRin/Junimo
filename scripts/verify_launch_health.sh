#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build_app.sh")"
HEALTH_PATH="${JUNIMO_HEALTH_PATH:-/tmp/junimo-health.json}"

rm -f "$HEALTH_PATH"
pkill -f "$APP_DIR/Contents/MacOS/Junimo" 2>/dev/null || true

JUNIMO_HEALTH_PATH="$HEALTH_PATH" open -n "$APP_DIR"

for _ in {1..20}; do
  if [[ -s "$HEALTH_PATH" ]]; then
    break
  fi
  sleep 0.25
done

if [[ ! -s "$HEALTH_PATH" ]]; then
  echo "Junimo health file was not written: $HEALTH_PATH" >&2
  exit 1
fi

python3 - "$HEALTH_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

def require(condition, message):
    if not condition:
        raise SystemExit(message)

require(data.get("status") == "ok", "health status is not ok")
require(data.get("pid", 0) > 0, "missing pid")
panel = data.get("panel", {})
require(panel.get("visible") is True, "panel is not visible")
require(panel.get("floating") is True, "panel is not floating")
frame = panel.get("frame", {})
require(frame.get("width", 0) >= 200, "panel width too small")
require(frame.get("height", 0) >= 40, "panel height too small")
require(panel.get("distanceFromTop", 999) <= 40, "panel is not anchored near the top system boundary")
console = data.get("console", {})
require(console.get("agents", 0) >= 2, "missing agents")
require(console.get("commands", 0) >= 4, "missing commands")
require(console.get("activities", 0) >= 1, "missing activity")
require(console.get("project") == "Junimo", "project profile mismatch")
preferences = console.get("preferences", {})
require(preferences.get("accent") in {"mint", "amber", "graphite"}, "invalid accent")
require(preferences.get("density") in {"comfortable", "compact"}, "invalid density")
require(preferences.get("expandedWidth", 0) >= 700, "expanded width too small")
print("Junimo launch health verified")
PY

pgrep -fl "$APP_DIR/Contents/MacOS/Junimo"
