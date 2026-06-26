#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build_app.sh")"
HEALTH_PATH="${JUNIMO_SCENARIO_HEALTH_PATH:-/tmp/junimo-functional-health.json}"
CORNER_NOTE_CACHE_PATH="${JUNIMO_SCENARIO_CORNER_NOTE_CACHE_PATH:-/tmp/junimo-functional-corner-note.cache}"

rm -f "$HEALTH_PATH" "$HEALTH_PATH.error" "$CORNER_NOTE_CACHE_PATH"

JUNIMO_HEALTH_PATH="$HEALTH_PATH" \
JUNIMO_HEALTH_SCENARIO=1 \
JUNIMO_CORNER_NOTE_CACHE_PATH="$CORNER_NOTE_CACHE_PATH" \
"$APP_DIR/Contents/MacOS/Junimo" >/tmp/junimo-functional-scenario.log 2>&1 &
pid=$!

cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in {1..20}; do
  if [[ -s "$HEALTH_PATH" ]]; then
    break
  fi
  sleep 0.25
done

if [[ ! -s "$HEALTH_PATH" ]]; then
  cat /tmp/junimo-functional-scenario.log >&2 || true
  cat "$HEALTH_PATH.error" >&2 2>/dev/null || true
  echo "Junimo functional scenario health file was not written: $HEALTH_PATH" >&2
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
panel = data.get("panel", {})
require(panel.get("distanceFromTop", 999) <= 40, "scenario panel is not anchored near the top system boundary")
console = data.get("console", {})
require(console.get("expanded") is True, "scenario did not expand console")
require(console.get("commandQuery") == "focus", "scenario did not update command query")
require(console.get("commands", 0) >= 1, "scenario command search returned no results")
require(console.get("sessions", 0) >= 2, "scenario did not create sessions")
require(console.get("activities", 0) >= 3, "scenario did not record activities")
require(console.get("latestActivity") == "Pomodoro started", "scenario latest activity mismatch")
preferences = console.get("preferences", {})
require(preferences.get("density") == "compact", "scenario did not update density")
require(preferences.get("expandedWidth") == 700, "compact width not applied")
corner = data.get("cornerNote", {})
require(corner.get("expanded") is True, "scenario did not expand corner note")
require(corner.get("noteLength", 0) > 0, "scenario did not write corner note text")
require(corner.get("todos", 0) >= 3, "scenario did not create corner todos")
print("Junimo functional scenario verified")
PY
