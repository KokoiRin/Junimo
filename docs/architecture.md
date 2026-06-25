# Architecture Notes

## Current Boundary

Junimo has three layers:

1. `Sources/Junimo`: macOS shell. Owns `NSApplication`, `NSPanel`, SwiftUI layout, hover events, and system notification delivery.
2. `Sources/JunimoCore`: Swift observable shell used by the current UI. It owns UI-ready snapshots and calls the C++ bridge for action and Pomodoro behavior.
3. `Core`: C++23 portable core. Owns the long-term domain model for agents, actions, activities, and Pomodoro lifecycle. `Core/include/junimo/core/c_api.h` exposes a narrow C ABI bridge consumed from Swift.

Swift/AppKit should remain responsible for native desktop behavior. C++ should own portable policy and state transitions.

## Launch Diagnostics

The app writes a local health snapshot at `/tmp/junimo-health.json` after the AppKit panel is shown. This is local-only diagnostic evidence for automated checks and contains process, panel, and C++ core-backed coordinator state. It is not telemetry and is not uploaded.

## Notch And Menu Bar Boundary

Junimo requests a top-center floating `NSPanel` position using the full screen frame. macOS can still clamp normal app windows/panels below the menu bar and camera notch reserved area. That means a floating capsule can sit at the highest system-allowed edge, but it cannot reliably occupy the actual menu bar/notch area through public AppKit panel APIs.

For real menu bar presence, Junimo also installs an `NSStatusItem` with Show and Quit commands. A status item is system-positioned in the menu bar rather than freely centered under the notch.

## Next Feature Scale

The tool should grow through replaceable modules:

- Adapter registry: Codex, Hermes, terminal commands, project scripts, and future automation providers register behind a common action interface.
- Project profiles: per-repository shortcuts, recent tasks, preferred agents, and safe working directories.
- Command palette: searchable actions that can be triggered from the expanded console.
- Session timeline: richer activity entries with status, duration, adapter, and failure reason.
- Pomodoro modes: focus/break presets, completion actions, and optional project/session association.
- Theme profiles: compact density, accent, material strength, and notch offset.

## Swift To C++ Bridge

The current app uses a narrow C ABI bridge instead of exposing C++ containers directly to Swift UI.

Current path:

1. Keep `junimo::core::TaskEngine` as the C++ owner of domain state.
2. Expose `JunimoCoreEngineRef` and small result structs from `c_api.h`.
3. Call the bridge from `Sources/JunimoCore/CppCoreBridge.swift` through `@_silgen_name`.
4. Map bridge snapshots into Swift `ObservableObject` state in `TaskCoordinator`.
5. Current bridge-backed behavior:
   - action dispatch
   - agent status transition for known agent actions
   - Pomodoro cancellation
   - Pomodoro completion notification request
   - command palette search
   - project profile snapshots
   - execution session snapshots
   - UI preferences for accent, density, expanded size, and top offset

This keeps UI iteration fast while steadily moving core behavior into C++23.

Next bridge steps:

- Move initial agent/action catalog snapshots fully into C++ UI state.
- Move activity feed trimming rules fully into C++.
- Add session cancellation/retry policies once real adapters report lifecycle events.
- Persist C++ UI preferences to a user config file after the in-memory model settles.
- Replace thread-local string snapshots with owned buffers if asynchronous bridge calls become necessary.
- Add adapter registry policy to C++ while keeping actual system execution in platform adapters.
