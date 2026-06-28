#!/usr/bin/env bash
set -euo pipefail

REPO="${JUNIMO_REPO:-KokoiRin/Junimo}"
APP_NAME="Junimo.app"
ASSET_NAME="${JUNIMO_ASSET_NAME:-Junimo-macos-arm64.zip}"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Junimo release installer currently supports Apple Silicon Macs only." >&2
  exit 1
fi

for tool in curl ditto find open pgrep; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/junimo-install.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

CURL_ARGS=(-fsSL --retry 3)

ZIP_PATH="$WORK_DIR/junimo.zip"
EXTRACT_DIR="$WORK_DIR/extract"
mkdir -p "$EXTRACT_DIR"

ASSET_URL="${JUNIMO_ASSET_URL:-https://github.com/$REPO/releases/latest/download/$ASSET_NAME}"
echo "Downloading Junimo latest release..."
curl "${CURL_ARGS[@]}" -L "$ASSET_URL" -o "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

APP_PATH="$(find "$EXTRACT_DIR" -maxdepth 3 -name "$APP_NAME" -type d -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Downloaded asset did not contain $APP_NAME." >&2
  exit 1
fi

if [[ -n "${JUNIMO_INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="$JUNIMO_INSTALL_DIR"
elif [[ -d /Applications && -w /Applications ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
fi

mkdir -p "$INSTALL_DIR"
DEST="$INSTALL_DIR/$APP_NAME"

if [[ -e "$DEST" ]]; then
  rm -rf "$DEST"
fi

ditto --norsrc "$APP_PATH" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Installed Junimo to $DEST"
if [[ "${JUNIMO_NO_OPEN:-0}" == "1" ]]; then
  echo "Skipping launch because JUNIMO_NO_OPEN=1."
  exit 0
fi

open "$DEST"
VERIFY_SECONDS="${JUNIMO_LAUNCH_VERIFY_SECONDS:-8}"
EXECUTABLE_PATH="$DEST/Contents/MacOS/Junimo"
for _ in $(seq 1 "$VERIFY_SECONDS"); do
  if pgrep -f "$EXECUTABLE_PATH" >/dev/null; then
    echo "Junimo launched and stayed running."
    exit 0
  fi
  sleep 1
done

echo "Junimo was installed to $DEST but did not stay running after launch." >&2
echo "Health file, if written: ${JUNIMO_HEALTH_PATH:-/tmp/junimo-health.json}" >&2
exit 1
