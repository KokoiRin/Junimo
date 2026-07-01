# Junimo

Junimo is a native macOS desktop tool that lives near the top-center screen area. The first slice provides a collapsed capsule that expands on hover into a lightweight local agent console.

## Install Latest Release

On an Apple Silicon Mac, install the latest published release without building
from source:

```bash
curl -fsSL https://raw.githubusercontent.com/KokoiRin/Junimo/main/scripts/install_latest.sh | bash
```

The installer downloads the latest GitHub Release zip directly, without using
the GitHub API, copies `Junimo.app` into `/Applications` when possible, falls
back to `~/Applications`, removes the download quarantine attribute, and
launches the app. The installer waits for the launched process to remain alive
for a short stability window before reporting success.

Launch diagnostics:

```bash
curl -fsSL https://raw.githubusercontent.com/KokoiRin/Junimo/main/scripts/collect_launch_diagnostics.sh | bash
```

The app writes lifecycle breadcrumbs to
`~/Library/Application Support/Junimo/launch.log`; the diagnostics script copies
that log, `/tmp/junimo-health.json`, capture-agent logs, and recent Junimo
system log lines into a desktop folder.

## Current Capabilities

- Top-center non-activating AppKit `NSPanel` hosted with SwiftUI.
- Collapsed capsule and hover-expanded console.
- Invisible L-shaped bottom-right screen-edge hot zone that opens an editable quick note and todo panel after a 0.5s dwell.
- Mock Codex/Hermes agent status.
- CLI/app-server-backed Codex monitor shell for quota source, known/cloud threads, realtime app-server events, exec JSONL lifecycle events, completion alerts, and persistent review attention.
- Chinese expanded console with module tabs for Codex, Focus, Note, and
  Screenshot script state, backed by a centralized UI copy table for future
  language switching.
- Adapter-mediated action clicks through `TaskCoordinator`.
- Recent activity recording.
- Basic accent theme control.
- Basic Pomodoro start, cancel, completion, and reminder request flow.
- C++23-backed agent/action catalog, recent activity feed, and active Pomodoro snapshot.
- C++23-backed quick note and todo cache at `~/Library/Application Support/Junimo/corner-note.cache`.
- C++23-backed command palette search.
- C++23-backed project profile snapshot.
- C++23-backed execution session timeline.
- C++23-backed UI preferences for accent and density.
- Optional background activity capture script writes 960px-wide low-quality JPEGs
  to `~/Documents/JunimoActivityCaptures` during the configured daytime window.

## Build And Test

The intended project shape is SwiftPM:

```bash
swift build
swift test
```

On this machine, SwiftPM currently fails while linking the manifest against the active CommandLineTools `PackageDescription` library. Until the local Xcode/CLT install is repaired, use the direct Swift compiler scripts:

```bash
scripts/test.sh
scripts/build.sh
```

The C++23 core framework is built and tested separately:

```bash
scripts/test_cpp.sh
scripts/build_cpp.sh
```

Swift `TaskCoordinator` now calls the C++23 core through a narrow C ABI bridge for action dispatch and Pomodoro lifecycle behavior. The bridge library is built by:

```bash
scripts/build_core_bridge.sh
```

Build and launch a macOS `.app` bundle:

```bash
scripts/build_app.sh
scripts/launch_app.sh
```

Build local distribution artifacts:

```bash
scripts/package_app.sh
```

The generated `.zip` and `.pkg` files are written to `.build/dist/`. See
[docs/distribution.md](docs/distribution.md) for signing and notarization notes.

Publish a GitHub Release from a tag:

```bash
git tag v<version>
git push origin v<version>
```

The release workflow builds and uploads Apple Silicon `.zip` and `.pkg`
artifacts.

Run the full available local verification suite:

```bash
scripts/verify.sh
```

`scripts/verify.sh` is the Chowa-ready harness for local iterations: it runs the
direct Swift smoke tests, C++ smoke test, app build, launch health check,
functional app scenario, OpenSpec validation, and whitespace
diff checks. For faster red/green loops, use `scripts/test.sh` for Swift-facing
coordinator and parser behavior and `scripts/test_cpp.sh` for the portable C++23
core.

Verify app launch health specifically:

```bash
scripts/verify_launch_health.sh
scripts/verify_functional_scenario.sh
cat /tmp/junimo-health.json
```

The health snapshot proves the `.app` initialized its AppKit panel and C++ core-backed state, which is useful when screenshot-based visual checks are blocked by the lock screen or secure desktop.

## Notch And Quit

Junimo requests top-center placement using the full screen frame. macOS may clamp normal floating panels below the menu bar/notch reserved area; this is a system boundary rather than an app-level layout bug. Junimo also installs a menu bar status item for native menu bar presence.

Quit options:

- Menu bar status item -> `Quit Junimo`.
- Terminal: `pkill -f ".build/app/Junimo.app/Contents/MacOS/Junimo"`.

Run the current app build:

```bash
.build/direct/Junimo
```

The app is a foreground process with accessory activation policy. Stop it from the launching terminal when finished.

The app bundle path is `.build/app/Junimo.app`. Launching it with `scripts/launch_app.sh` leaves a macOS app process running; stop it with:

```bash
pkill -f ".build/app/Junimo.app/Contents/MacOS/Junimo"
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the Swift/AppKit shell, current Swift coordinator, new C++23 core boundary, and next feature expansion plan.
See [docs/codex-integration.md](docs/codex-integration.md) for the researched Codex quota, thread, cloud task, realtime, and review-attention integration path.
See [docs/testing.md](docs/testing.md) for the test pyramid and harness strategy.

## OpenSpec

Long-lived requirements live in `openspec/specs/`; archived change designs and tasks live under `openspec/changes/archive/`. Validate the current OpenSpec state with:

```bash
openspec validate --all --strict
```

New Chowa iteration notes live under `chowa/`.
