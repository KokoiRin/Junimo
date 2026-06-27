## Why

Junimo needs a richer workbench surface than one-off activities. When users start agents, project actions, or focus workflows, the app should show a small session timeline that can later map to real Codex/Hermes/terminal runs.

The timeline should be owned by the C++23 core so future adapters share one execution-state model.

## What Changes

- Add C++23 execution session models and status values.
- Record sessions when actions or Pomodoro sessions start.
- Expose recent session snapshots through the C ABI bridge.
- Add Swift models/coordinator state for recent sessions.
- Add an expanded-console session timeline section.
- Add tests covering C++ and Swift session snapshots.

## Capabilities

### New Capabilities
- `session-timeline`: C++ core-backed execution sessions shown in the Junimo console.

### Modified Capabilities

## Impact

- Extends `Core/` models, `TaskEngine`, and C API.
- Extends Swift bridge/coordinator and SwiftUI surface.
- No real shell/system operation execution is introduced.
