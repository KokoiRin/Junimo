#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
mkdir -p "$DIST_DIR"

APP_DIR="$("$ROOT_DIR/scripts/build_app.sh")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/junimo-package.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_COPY="$WORK_DIR/Junimo.app"
ditto --norsrc "$APP_DIR" "$APP_COPY"
xattr -cr "$APP_COPY" 2>/dev/null || true

SIGN_IDENTITY="${CODESIGN_IDENTITY:-"-"}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_COPY" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_COPY" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_COPY/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP_COPY/Contents/MacOS/Junimo" | tr ' ' '-')"
ZIP_PATH="$DIST_DIR/Junimo-${VERSION}-macos-${ARCHS}.zip"

ditto -c -k --keepParent --norsrc "$APP_COPY" "$ZIP_PATH"
unzip -t "$ZIP_PATH" >/dev/null

echo "$ZIP_PATH"
