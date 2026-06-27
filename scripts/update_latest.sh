#!/usr/bin/env bash
set -euo pipefail

REPO="${JUNIMO_REPO:-KokoiRin/Junimo}"
APP_NAME="Junimo.app"
PROCESS_NAME="Junimo"

for tool in curl pgrep pkill; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if [[ -z "${JUNIMO_INSTALL_DIR:-}" ]]; then
  if [[ -d "/Applications/$APP_NAME" ]]; then
    export JUNIMO_INSTALL_DIR="/Applications"
  elif [[ -d "$HOME/Applications/$APP_NAME" ]]; then
    export JUNIMO_INSTALL_DIR="$HOME/Applications"
  fi
fi

if [[ "${JUNIMO_DRY_RUN:-0}" == "1" ]]; then
  echo "Would update Junimo in ${JUNIMO_INSTALL_DIR:-the default install location}."
  exit 0
fi

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "Stopping running Junimo before update..."
  pkill -TERM -x "$PROCESS_NAME" 2>/dev/null || true

  for _ in {1..20}; do
    if ! pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "Junimo is still running; please quit it and retry." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || true)"
LOCAL_INSTALLER="$SCRIPT_DIR/install_latest.sh"

if [[ -x "$LOCAL_INSTALLER" ]]; then
  "$LOCAL_INSTALLER"
else
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/scripts/install_latest.sh" | bash
fi
