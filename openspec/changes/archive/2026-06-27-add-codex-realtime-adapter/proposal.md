## Why

Junimo can show Codex diagnostic snapshots, but it still behaves like a polling status display. The next product-critical step is a real Codex adapter that keeps the top console updated from live app-server and `codex exec --json` events.

## What Changes

- Add a Codex realtime event model for quota updates, thread status changes, and exec JSONL lifecycle events.
- Parse app-server JSON-RPC notifications into coordinator-ready updates.
- Parse Junimo-launched `codex exec --json` JSONL events into the same thread update path.
- Replace the timer-only monitor bridge with a bridge that can start a background realtime stream and still fall back to periodic snapshots.
- Keep all shell/process and Codex protocol concerns in Swift adapters, leaving SwiftUI and C++ core boundaries unchanged.

## Capabilities

### New Capabilities
- `codex-realtime-adapter`: Background Codex event ingestion for quota, thread, and completion state.

### Modified Capabilities
- `codex-monitor`: Updates can arrive from realtime adapter events, not only snapshot polling.

## Impact

- Extends `Sources/JunimoCore/CodexStatusProvider.swift` with event parsing and stream abstractions.
- Extends `Sources/Junimo/CodexMonitorRefreshBridge.swift` to own realtime stream lifecycle.
- Extends `TaskCoordinator` tests for active-to-terminal notification behavior through realtime events.
- Updates Codex integration docs and progress notes.
