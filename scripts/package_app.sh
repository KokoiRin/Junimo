#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
mkdir -p "$DIST_DIR"
export COPYFILE_DISABLE=1

APP_DIR="$("$ROOT_DIR/scripts/build_app.sh")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/junimo-package.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_COPY="$WORK_DIR/Junimo.app"
ditto --norsrc "$APP_DIR" "$APP_COPY"
find "$APP_COPY" -name '._*' -delete
chmod -R u+rwX,go+rX "$APP_COPY"
xattr -cr "$APP_COPY" 2>/dev/null || true

SIGN_IDENTITY="${CODESIGN_IDENTITY:-"-"}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_COPY" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_COPY" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_COPY/Contents/Info.plist")"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_COPY/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP_COPY/Contents/MacOS/Junimo" | tr ' ' '-')"
ZIP_PATH="$DIST_DIR/Junimo-${VERSION}-macos-${ARCHS}.zip"
PKG_PATH="$DIST_DIR/Junimo-${VERSION}-macos-${ARCHS}.pkg"

ditto -c -k --keepParent --norsrc "$APP_COPY" "$ZIP_PATH"
unzip -t "$ZIP_PATH" >/dev/null

PKG_ROOT="$WORK_DIR/pkgroot"
mkdir -p "$PKG_ROOT/Applications"
ditto --norsrc "$APP_COPY" "$PKG_ROOT/Applications/Junimo.app"
find "$PKG_ROOT" -name '._*' -delete

pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$PKG_PATH" >/dev/null

if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
  SIGNED_PKG_PATH="$DIST_DIR/Junimo-${VERSION}-macos-${ARCHS}-signed.pkg"
  productsign --sign "$INSTALLER_SIGN_IDENTITY" "$PKG_PATH" "$SIGNED_PKG_PATH" >/dev/null
  PKG_PATH="$SIGNED_PKG_PATH"
fi

echo "$ZIP_PATH"
echo "$PKG_PATH"
