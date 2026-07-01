#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CAPTURE_SCRIPT="$ROOT_DIR/scripts/capture_activity_snapshot.py"

export ACTIVITY_CAPTURE_DIR="${ACTIVITY_CAPTURE_DIR:-$HOME/Documents/JunimoActivityCaptures}"
export ACTIVITY_CAPTURE_START_DATE="${ACTIVITY_CAPTURE_START_DATE:-$(date +%Y-%m-%d)}"
export ACTIVITY_CAPTURE_MAX_WIDTH="${ACTIVITY_CAPTURE_MAX_WIDTH:-960}"
export ACTIVITY_CAPTURE_JPEG_QUALITY="${ACTIVITY_CAPTURE_JPEG_QUALITY:-35}"
export ACTIVITY_CAPTURE_WINDOW_START="${ACTIVITY_CAPTURE_WINDOW_START:-1000}"
export ACTIVITY_CAPTURE_WINDOW_END="${ACTIVITY_CAPTURE_WINDOW_END:-2200}"
export ACTIVITY_CAPTURE_INTERVAL_SECONDS="${ACTIVITY_CAPTURE_INTERVAL_SECONDS:-60}"

echo "Junimo manual activity capture"
echo "Captures: $ACTIVITY_CAPTURE_DIR"
echo "Window:   $ACTIVITY_CAPTURE_WINDOW_START-$ACTIVITY_CAPTURE_WINDOW_END"
echo "Every:    ${ACTIVITY_CAPTURE_INTERVAL_SECONDS}s"
echo
echo "Keep this terminal open. Press Ctrl-C to stop."
echo "Screen Recording permission belongs to this terminal/Python process."
echo

while true; do
  started="$(date '+%Y-%m-%d %H:%M:%S')"
  if output="$(/usr/bin/python3 "$CAPTURE_SCRIPT" 2>&1)"; then
    echo "$started capture-ok $output"
  else
    code=$?
    echo "$started capture-failed code=$code $output" >&2
  fi
  sleep "$ACTIVITY_CAPTURE_INTERVAL_SECONDS"
done
