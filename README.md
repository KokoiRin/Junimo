# Junimo

Junimo is a native macOS desktop tool that lives near the top-center screen area. The first slice provides a collapsed capsule that expands on hover into a lightweight local agent console.

## Current Capabilities

- Top-center non-activating AppKit `NSPanel` hosted with SwiftUI.
- Collapsed capsule and hover-expanded console.
- Mock Codex/Hermes agent status.
- Adapter-mediated action clicks through `TaskCoordinator`.
- Recent activity recording.
- Basic accent theme control.
- Basic Pomodoro start, cancel, completion, and reminder request flow.
- C++23-backed command palette search.
- C++23-backed project profile snapshot.
- C++23-backed execution session timeline.
- C++23-backed UI preferences for accent and density.

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

Run the full available local verification suite:

```bash
scripts/verify.sh
```

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

- Expanded console power button.
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

## OpenSpec

The active change is:

```bash
openspec validate bootstrap-hover-console --strict
openspec validate add-cpp23-core-framework --strict
openspec validate bridge-swift-to-cpp-core --strict
openspec validate add-command-palette-profiles --strict
openspec validate add-session-timeline --strict
openspec validate add-ui-preferences-core --strict
openspec validate add-launch-health-snapshot --strict
```

Design and tasks live under `openspec/changes/bootstrap-hover-console/`.
