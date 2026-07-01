#!/usr/bin/env bash
set -euo pipefail

PID_FILE="$HOME/Library/Application Support/Junimo/ActivityCapture/activity-capture-loop.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "Junimo activity capture loop is not running."
  exit 0
fi

PID="$(cat "$PID_FILE")"
if [[ -z "$PID" ]]; then
  rm -f "$PID_FILE"
  echo "Junimo activity capture loop is not running."
  exit 0
fi

if kill "$PID" 2>/dev/null; then
  rm -f "$PID_FILE"
  echo "Stopped Junimo activity capture loop pid=$PID"
else
  rm -f "$PID_FILE"
  echo "Junimo activity capture loop pid=$PID was not running."
fi
