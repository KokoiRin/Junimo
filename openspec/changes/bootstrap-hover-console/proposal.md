## Why

Junimo needs a native macOS desktop surface that stays near the top-center notch area and gives quick access to local agents, developer tools, project actions, and lightweight status without introducing a web runtime or real agent protocol too early.

This first change establishes a runnable Swift/SwiftUI foundation and one complete interaction chain so future Codex, Hermes, terminal, and automation integrations can be added behind adapters.

## What Changes

- Create a SwiftPM-based macOS application using Swift, SwiftUI, and AppKit for a non-activating floating panel.
- Add the first hover console chain: collapsed capsule, hover expansion, mock agent status, shortcut actions, recent activity, action-triggered status/activity updates, and delayed collapse after hover exit.
- Route UI-triggered work through a `TaskCoordinator` and adapter boundary instead of executing shell or system operations from views.
- Add basic theme customization state for the first UI frame.
- Add a simple Pomodoro capability with create, cancel, and completion notification behavior, backed by testable domain logic.
- Document progress, verification commands, and known limitations.

## Capabilities

### New Capabilities
- `hover-console`: macOS floating top-center capsule and expanded console interaction, including mock agents, actions, activity, theme state, and adapter-based task execution.
- `pomodoro-timer`: Basic Pomodoro lifecycle for creating, cancelling, completing, and notifying timer sessions.

### Modified Capabilities

## Impact

- New SwiftPM manifest and macOS application sources under `Sources/Junimo`.
- New test targets for coordinator/domain behavior under `Tests/JunimoTests`.
- New OpenSpec documents under `openspec/changes/bootstrap-hover-console`.
- New README and progress documentation describing how to build, test, and run the current app.
