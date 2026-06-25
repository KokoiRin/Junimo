## Why

Junimo now has a runnable Swift/AppKit surface, but the next phase needs a stronger native foundation: a real macOS app bundle for launch verification and a C++23 core that can grow into the primary domain/runtime layer.

The C++ core should start small, testable, and independent from Swift UI details so future agent orchestration, task planning, project indexing, and timers can move behind a stable boundary.

## What Changes

- Add a `.app` bundle build script so Junimo can be launched and inspected as a desktop app instead of only as a bare executable.
- Add a C++23 core framework skeleton with domain models for actions, agents, activities, and Pomodoro sessions.
- Add C++ tests and build scripts using Apple clang directly because `cmake` is not installed in the current environment.
- Add architecture notes for the next feature scale-up: workspace quick actions, command palette, adapter registry, project profiles, and a Swift-to-C++ bridge.
- Update documentation with verified launch state and the current lock-screen limitation for visual UI testing.

## Capabilities

### New Capabilities
- `app-bundle-launch`: Build and launch Junimo as a macOS `.app` bundle with a stable process identity.
- `cpp23-core-framework`: Build and test a C++23 core library skeleton that owns portable Junimo domain behavior.
- `visual-validation`: Record desktop visual validation requirements and lock-screen limitations.

### Modified Capabilities

## Impact

- New C++ files under `Core/`.
- New scripts under `scripts/` for C++ build/test and app bundle build/launch.
- Updated README and progress docs.
- No Electron, Tauri, WebView, C++ UI toolkit, or real agent protocol is introduced.
