#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

export ACTIVITY_CAPTURE_DIR="${ACTIVITY_CAPTURE_DIR:-$HOME/Documents/JunimoActivityCaptures}"
export ACTIVITY_CAPTURE_START_DATE="${ACTIVITY_CAPTURE_START_DATE:-$(date +%Y-%m-%d)}"
export ACTIVITY_CAPTURE_MAX_WIDTH="${ACTIVITY_CAPTURE_MAX_WIDTH:-960}"
export ACTIVITY_CAPTURE_JPEG_QUALITY="${ACTIVITY_CAPTURE_JPEG_QUALITY:-35}"
export ACTIVITY_CAPTURE_WINDOW_START="${ACTIVITY_CAPTURE_WINDOW_START:-1000}"
export ACTIVITY_CAPTURE_WINDOW_END="${ACTIVITY_CAPTURE_WINDOW_END:-2200}"
export ACTIVITY_CAPTURE_INTERVAL_SECONDS="${ACTIVITY_CAPTURE_INTERVAL_SECONDS:-60}"

mkdir -p "$HOME/Library/Application Support/Junimo/ActivityCapture"

echo "Junimo activity capture loop"
echo "Captures: $ACTIVITY_CAPTURE_DIR"
echo "Window:   $ACTIVITY_CAPTURE_WINDOW_START-$ACTIVITY_CAPTURE_WINDOW_END"
echo "Every:    ${ACTIVITY_CAPTURE_INTERVAL_SECONDS}s"
echo
echo "Keep this window open while capture is running."
echo

exec /usr/bin/python3 scripts/run_activity_capture_loop.py
