# Junimo Distribution

Junimo can be packaged locally as a macOS app archive and an installer package.

## Install From GitHub Release

On an Apple Silicon Mac, an agent can install the latest published release with:

```bash
curl -fsSL https://raw.githubusercontent.com/KokoiRin/Junimo/main/scripts/install_latest.sh | bash
```

The script downloads the latest GitHub Release zip asset matching
`macos-arm64.zip`, installs `Junimo.app` into `/Applications` when writable, and
falls back to `~/Applications`.

Useful overrides:

```bash
JUNIMO_INSTALL_DIR="$HOME/Applications" scripts/install_latest.sh
JUNIMO_REPO="KokoiRin/Junimo" scripts/install_latest.sh
JUNIMO_NO_OPEN=1 scripts/install_latest.sh
```

## Build Local Artifacts

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

## Release Automation

Pushing a version tag runs `.github/workflows/release.yml`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow verifies it is running on an Apple Silicon macOS runner, verifies
the app, runs `scripts/package_app.sh`, and uploads the generated Apple Silicon
`.zip` and `.pkg` files to the GitHub Release.
