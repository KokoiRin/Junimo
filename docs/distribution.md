# Junimo Distribution

Junimo can be packaged locally as a macOS app archive and an installer package.

```bash
scripts/package_app.sh
```

The artifacts are written to:

```text
.build/dist/
```

The script currently creates:

- `Junimo-<version>-macos-<arch>.zip`: drag-copy app archive.
- `Junimo-<version>-macos-<arch>.pkg`: installer that places `Junimo.app` in `/Applications`.

## Signing

By default, the script ad-hoc signs the app with `codesign -s -`. This is enough
for local testing, but it is not enough for a public macOS release.

For a distributable build, provide Apple Developer ID identities:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
scripts/package_app.sh
```

## Notarization

To install smoothly on other Macs, the signed package should be notarized and
stapled with Apple notary service:

```bash
xcrun notarytool submit .build/dist/Junimo-*-signed.pkg \
  --keychain-profile "<notary-profile>" \
  --wait

xcrun stapler staple .build/dist/Junimo-*-signed.pkg
```

Create the notary profile once with:

```bash
xcrun notarytool store-credentials "<notary-profile>" \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

Unsigned or ad-hoc signed builds can still be copied or installed for local
testing, but another Mac may require right-clicking the app and choosing Open, or
adjusting Gatekeeper settings.
