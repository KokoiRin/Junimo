#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build_app.sh")"

pkill -f "$APP_DIR/Contents/MacOS/Junimo" 2>/dev/null || true
open -n "$APP_DIR"
sleep 1

if pgrep -fl "$APP_DIR/Contents/MacOS/Junimo" >/dev/null; then
  pgrep -fl "$APP_DIR/Contents/MacOS/Junimo"
else
  echo "Junimo.app did not stay running" >&2
  exit 1
fi
