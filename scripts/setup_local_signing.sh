#!/usr/bin/env bash
set -euo pipefail
umask 077

# 一次性创建 Junimo 本机开发身份。私钥导入登录钥匙串后删除，重跑复用同一证书。
SIGNING_DIR="$HOME/Library/Application Support/Junimo/signing"
CERTIFICATE="$SIGNING_DIR/certificate.pem"
PRIVATE_KEY="$SIGNING_DIR/private-key.pem"
KEYCHAIN="$(security default-keychain -d user | tr -d '"' | sed 's/^ *//;s/ *$//')"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ ! -f "$CERTIFICATE" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj '/CN=Junimo Local Development/' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$PRIVATE_KEY" -out "$CERTIFICATE" >/dev/null 2>&1
fi

IDENTITY="$(openssl x509 -in "$CERTIFICATE" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
[[ "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo "Invalid local signing certificate" >&2; exit 1; }
IDENTITIES="$(security find-identity -p codesigning "$KEYCHAIN")"
if [[ "$IDENTITIES" != *"$IDENTITY"* ]]; then
  [[ -f "$PRIVATE_KEY" ]] || { echo "Junimo signing key is missing from the keychain; restore the existing identity before rebuilding." >&2; exit 1; }
  ARCHIVE="$(mktemp "$SIGNING_DIR/import.XXXXXX")"
  trap 'rm -f "$ARCHIVE"' EXIT
  # macOS 不可靠地接受空口令 PKCS#12；临时口令不保存、不输出，导入后归档立即删除。
  JUNIMO_ARCHIVE_PASSWORD="$(openssl rand -hex 24)"
  export JUNIMO_ARCHIVE_PASSWORD
  openssl pkcs12 -export -inkey "$PRIVATE_KEY" -in "$CERTIFICATE" -out "$ARCHIVE" \
    -passout env:JUNIMO_ARCHIVE_PASSWORD -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
  security import "$ARCHIVE" -f pkcs12 -k "$KEYCHAIN" -P "$JUNIMO_ARCHIVE_PASSWORD" -T /usr/bin/codesign
  unset JUNIMO_ARCHIVE_PASSWORD
  rm -f "$ARCHIVE"
fi
rm -f "$PRIVATE_KEY"

# 只在当前用户范围信任该证书的代码签名用途，不更改系统根证书或网页证书信任。
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERTIFICATE"
VALID_IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN")"
[[ "$VALID_IDENTITIES" == *"$IDENTITY"* ]] || { echo "Junimo signing identity is not trusted for code signing yet." >&2; exit 1; }
printf '%s\n' "$IDENTITY" > "$SIGNING_DIR/identity"
echo "Junimo local signing identity is ready. Future builds will reuse it."
