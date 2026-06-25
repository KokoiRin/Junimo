#!/usr/bin/env bash
set -euo pipefail

REPO="${JUNIMO_REPO:-KokoiRin/Junimo}"
APP_NAME="Junimo.app"
ASSET_PATTERN="${JUNIMO_ASSET_PATTERN:-macos-arm64.zip}"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Junimo release installer currently supports Apple Silicon Macs only." >&2
  exit 1
fi

for tool in curl ditto find open; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/junimo-install.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_JSON="$WORK_DIR/release.json"
CURL_ARGS=(-fsSL --retry 3)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

curl "${CURL_ARGS[@]}" "$API_URL" -o "$RELEASE_JSON"

TAG_NAME="$(awk -F '"' '/"tag_name"/ { print $4; exit }' "$RELEASE_JSON")"
ASSET_URL="$(awk -F '"' -v pattern="$ASSET_PATTERN" '/"browser_download_url"/ { if ($4 ~ pattern) { print $4; exit } }' "$RELEASE_JSON")"

if [[ -z "$ASSET_URL" ]]; then
  echo "Could not find a release asset matching '$ASSET_PATTERN' in $REPO latest release." >&2
  exit 1
fi

ZIP_PATH="$WORK_DIR/junimo.zip"
EXTRACT_DIR="$WORK_DIR/extract"
mkdir -p "$EXTRACT_DIR"

echo "Downloading Junimo ${TAG_NAME:-latest}..."
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
echo "Junimo launched."
