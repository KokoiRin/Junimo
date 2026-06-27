#!/usr/bin/env zsh
set -euo pipefail

LABEL="com.bytedance.junimo.activity-capture"
TARGET_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -f "$TARGET_PLIST" ]]; then
  launchctl bootout "gui/$UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
  rm -f "$TARGET_PLIST"
fi

printf 'Uninstalled %s\n' "$LABEL"
