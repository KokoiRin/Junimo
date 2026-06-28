#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${JUNIMO_DIAGNOSTICS_DIR:-$HOME/Desktop/junimo-diagnostics-$(date +%Y%m%d-%H%M%S)}"
HEALTH_PATH="${JUNIMO_HEALTH_PATH:-/tmp/junimo-health.json}"
APP_PATH="${JUNIMO_APP_PATH:-/Applications/Junimo.app}"
LAUNCH_LOG="$HOME/Library/Application Support/Junimo/launch.log"
CAPTURE_SUPPORT="$HOME/Library/Application Support/Junimo/ActivityCapture"

mkdir -p "$OUT_DIR"

copy_if_exists() {
  local source="$1"
  local name="$2"
  if [[ -e "$source" ]]; then
    cp -R "$source" "$OUT_DIR/$name"
  fi
}

copy_if_exists "$HEALTH_PATH" "junimo-health.json"
copy_if_exists "$HEALTH_PATH.error" "junimo-health.json.error"
copy_if_exists "$LAUNCH_LOG" "launch.log"
copy_if_exists "$CAPTURE_SUPPORT/activity-capture.out.log" "activity-capture.out.log"
copy_if_exists "$CAPTURE_SUPPORT/activity-capture.err.log" "activity-capture.err.log"

{
  echo "date=$(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "app_path=$APP_PATH"
  if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null | sed 's/^/version=/'
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null | sed 's/^/build=/'
    /usr/libexec/PlistBuddy -c 'Print :NSSupportsAutomaticTermination' "$APP_PATH/Contents/Info.plist" 2>/dev/null | sed 's/^/supports_automatic_termination=/'
  fi
  echo
  ps -axo pid,etime,stat,command | grep -F "Junimo.app/Contents/MacOS/Junimo" | grep -v grep || true
  echo
  launchctl print "gui/$UID/com.bytedance.junimo.activity-capture" 2>&1 || true
} > "$OUT_DIR/summary.txt"

log show \
  --style syslog \
  --last "${JUNIMO_LOG_LAST:-20m}" \
  --predicate 'process == "Junimo" OR eventMessage CONTAINS "Junimo" OR eventMessage CONTAINS "_NSEnableAutomaticTerminationAndLog" OR eventMessage CONTAINS "No windows open yet"' \
  > "$OUT_DIR/system-log.txt" 2>&1 || true

echo "$OUT_DIR"
