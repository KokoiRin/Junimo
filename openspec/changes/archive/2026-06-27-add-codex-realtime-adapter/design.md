## Context

`TaskCoordinator` already owns `CodexMonitorSnapshot`, `refreshCodexMonitor(...)`, and `updateCodexThread(...)`. `CodexCLIStatusProvider` can probe `codex doctor`, `codex cloud list`, and a short-lived `codex app-server --stdio` request. The missing piece is a long-lived event path that can keep the same coordinator state fresh.

Codex app-server and `codex exec --json` are platform/protocol integrations. They belong in Swift adapter code, not in C++ core. C++ remains the owner of portable app state such as actions, activities, Pomodoro, preferences, and command catalog.

## Goals / Non-Goals

**Goals:**
- Use one coordinator event surface for app-server notifications and exec JSONL events.
- Keep realtime process work off the SwiftUI render path.
- Preserve existing snapshot polling as setup/fallback evidence.
- Make event parsing testable without starting a real Codex daemon.
- Request completion/failure alerts when known threads transition from running or waiting to completed or failed.

**Non-Goals:**
- Do not build a generic adapter registry in this change.
- Do not add new visible controls for launching arbitrary Codex prompts.
- Do not require a live Codex daemon in local tests.
- Do not move Codex protocol logic into C++.

## Decisions

1. **Coordinator receives structured events**
   - Add a `CodexRealtimeEvent` enum with `usage`, `thread`, and `finding` cases.
   - `TaskCoordinator.applyCodexRealtimeEvent(...)` mutates `codexMonitor` and reuses `updateCodexThread(...)` for terminal transition alerts.

2. **App-server stream parses JSON-RPC notifications**
   - A `CodexRealtimeEventParser` maps `account/rateLimitsUpdated`, `thread/statusChanged`, `turn/completed`, `thread/closed`, and related method names into `CodexRealtimeEvent`.
   - Unknown notifications are ignored, not treated as errors.

3. **Exec JSONL uses the same thread path**
   - `thread.started` and `turn.started` produce running updates.
   - `turn.completed` produces completed updates.
   - `turn.failed` and `error` produce failed updates.
   - Missing titles fall back to a stable local thread label.

4. **Realtime bridge remains optional**
   - `CodexMonitorRefreshBridge` starts periodic snapshots as before.
   - If a realtime stream is available, it starts once and publishes parsed events onto the main actor.
   - Environment opt-out remains available through `JUNIMO_DISABLE_CODEX_MONITOR=1`.

## Risks / Trade-offs

- **Codex notification shapes may drift** -> Event parsing is defensive and covered by fixture-style tests.
- **Long-lived stdio processes can fail** -> The stream emits a degraded finding and periodic snapshot polling remains in place.
- **Event model may later generalize into adapter registry** -> This change intentionally keeps Codex-specific types until another real adapter proves the abstraction.
