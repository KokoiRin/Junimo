## Context

The current UI runs through `TaskCoordinator`, and `Core/` has a working C++23 `TaskEngine`. The missing piece is a stable boundary so Swift can own UI state while C++ owns portable domain transitions.

## Goals / Non-Goals

**Goals:**
- Keep the SwiftUI/AppKit layer unchanged.
- Expose only coarse C++ core operations needed by the current app.
- Avoid passing C++ containers/classes directly into Swift.
- Keep returned strings valid long enough for Swift to copy them.
- Preserve existing direct script verification.

**Non-Goals:**
- Do not introduce a full generated binding system.
- Do not migrate every Swift model to C++ in one step.
- Do not add real external agent execution.

## Decisions

1. **Use C ABI handles**
   - `JunimoCoreEngineRef` is opaque to Swift.
   - Swift creates/destroys it through C functions.
   - This avoids relying on Swift C++ interop while the local SwiftPM/CLT setup is unstable.

2. **Return value snapshots**
   - C functions return small structs with primitive fields and `const char*`.
   - The bridge stores result strings in thread-local storage so Swift can copy them immediately.
   - Swift owns no C++ memory.

3. **Swift coordinator remains observable**
   - Swift still publishes arrays and UI state.
   - C++ decides action result, agent status transitions, Pomodoro cancellation/completion, and notification request data.

## Risks / Trade-offs

- **Temporary model duplication remains** -> The bridge lets us migrate behavior first; model storage can move later.
- **Thread-local string snapshots are not a long-term API** -> Acceptable for current synchronous UI calls; replace with owned buffers if async/native plugin use appears.
- **Direct scripts get more complex** -> Centralize C++ bridge build in `scripts/build_core_bridge.sh`.
