#!/usr/bin/env bash
set -euo pipefail

# 验证更新后的应用仍满足旧版签名身份；只修改测试副本，不启动副本或触碰授权记录。
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/app/Junimo.app"
IDENTITY_FILE="$HOME/Library/Application Support/Junimo/signing/identity"
IDENTITY="${JUNIMO_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  [[ -f "$IDENTITY_FILE" ]] || { echo "Configure fixed signing first." >&2; exit 1; }
  IDENTITY="$(cat "$IDENTITY_FILE")"
fi
[[ "$IDENTITY" != '-' ]] || { echo "Fixed identity required." >&2; exit 1; }
VERIFY_DIR="$(mktemp -d "$ROOT_DIR/.build/signing-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
COPY="$VERIFY_DIR/Junimo.app"
ditto "$APP_DIR" "$COPY"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion signing-verification' "$COPY/Contents/Info.plist"
codesign --force --timestamp=none --sign "$IDENTITY" "$COPY"

requirement() { codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'; }
code_hash() { codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
BEFORE="$(requirement "$APP_DIR")"
AFTER="$(requirement "$COPY")"
[[ -n "$BEFORE" && "$BEFORE" == "$AFTER" && "$BEFORE" != *'cdhash '* ]] || {
  echo "App identity is not stable across content changes." >&2; exit 1;
}
FIRST_HASH="$(code_hash "$APP_DIR")"
SECOND_HASH="$(code_hash "$COPY")"
[[ -n "$FIRST_HASH" && -n "$SECOND_HASH" && "$FIRST_HASH" != "$SECOND_HASH" ]] || {
  echo "Verification must compare different signed content." >&2; exit 1;
}
codesign --verify --deep --strict "$APP_DIR"
codesign --verify --deep --strict -R="$BEFORE" "$COPY"
echo "PASS: different app content preserves the same certificate-bound identity and satisfies the previous requirement."
