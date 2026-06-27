# Design: Split Codex Status Provider Boundaries

## Target Type

[P0][架构重构]

## Core Behavior Semantics

当 Junimo 读取 Codex quota、thread snapshot、realtime event 或 exec lifecycle 时，外部进程和协议 I/O 应该只发生在 Codex adapter/transport 层；parser 只把协议 payload 转成 typed model；monitor/provider 只组合 typed result 并把它交给 `CodexFeature` 或兼容 coordinator。

## Current Diagnosis

`Sources/JunimoCore/CodexStatusProvider.swift` is 1300+ lines and contains multiple layers with different change reasons:

- contracts: `CodexCommandRunning`, `CodexMonitorSnapshotProviding`, `CodexRealtimeEventStreaming`
- process runner: `ProcessCodexCommandRunner`
- short app-server query: `ProcessCodexAppServerClient`
- long-running app-server realtime stream: `ProcessCodexAppServerEventStream`
- long-running exec JSONL stream: `ProcessCodexExecEventStream`
- provider composition: `CodexCLIStatusProvider`
- pure snapshot parser: `CodexStatusParser`
- pure realtime parser: `CodexRealtimeEventParser`

The behavior is already covered by direct smoke tests and fake-backed app bridge tests. This makes it a good moment to split file boundaries without changing product semantics.

## Target File Boundaries

### `CodexAdapterContracts.swift`

- Responsibility: public protocols and typed adapter results/events.
- Not responsible for: process execution, parsing, or feature state.
- Owner: Codex adapter boundary.
- Test surface: compile-time imports and existing fake providers/streams.

### `CodexProcessRunner.swift`

- Responsibility: run `codex` process commands and return raw stdout/stderr/exit code.
- Not responsible for: interpreting doctor/cloud output or feature state.
- Side effects: process execution only.
- Test surface: provider tests use `CodexCommandRunning` fakes; real process execution stays out of unit tests.

### `CodexAppServerClient.swift`

- Responsibility: short-lived app-server JSON-RPC query for quota and thread list.
- Not responsible for: lifecycle policy, UI priority, review attention, or provider fallback.
- Side effects: process I/O over stdio.
- Test surface: `CodexAppServerQuerying` fakes and parser fixtures.

### `CodexRealtimeStreams.swift`

- Responsibility: long-running app-server and exec JSONL streams.
- Not responsible for: product state or review attention.
- Side effects: process lifecycle, stream read handlers, cancellation.
- Test surface: `CodexRealtimeEventStreaming` fakes and parser fixture tests.

### `CodexStatusParser.swift`

- Responsibility: pure parsing from doctor/cloud/app-server snapshots into typed monitor models.
- Not responsible for: launching processes or applying state to `CodexFeature`.
- Test surface: direct parser fixture tests.

### `CodexRealtimeEventParser.swift`

- Responsibility: pure parsing from app-server notifications and exec JSONL events into `CodexRealtimeEvent`.
- Not responsible for: process lifecycle or feature state.
- Test surface: direct realtime fixture tests.

### `CodexMonitorService.swift`

- Responsibility: compose provider snapshots and realtime stream events into a sink protocol.
- Not responsible for: parsing raw protocol payloads, owning feature state, or launching UI.
- Interface:
  - `CodexMonitorEventSink` with `refreshCodexMonitor`, `applyCodexRealtimeEvent`, and `applyCodexIntegrationFinding`.
  - A service that can start/stop the realtime stream and trigger a provider snapshot refresh.
- Test surface: fake provider, fake stream, and fake sink integration tests.

## Migration Strategy

1. Add `CodexMonitorEventSink` and a small service skeleton while preserving `CodexMonitorRefreshBridge` behavior.
2. Move contract types out of `CodexStatusProvider.swift`.
3. Move process runner and app-server client out.
4. Move realtime streams out.
5. Move pure parsers out.
6. Leave `CodexStatusProvider.swift` as the snapshot provider file or shrink it to only `CodexCLIStatusProvider`.
7. Update docs and opportunities after tests prove behavior unchanged.

## Verification Strategy

- `scripts/test.sh`: covers `CodexFeature`, parser fixtures, provider fakes, and app bridge fake stream behavior.
- `scripts/build.sh`: ensures app target still compiles after file split.
- `openspec validate --all --strict`: ensures specs remain aligned.
- `git diff --check`: whitespace/static diff check.
- `scripts/verify_ci.sh` before archive if the slice changes public app/core behavior.

## Current Non-Decisions

- Do not create a generic adapter registry yet.
- Do not change Codex app-server protocol assumptions beyond existing tests.
- Do not make `CodexMonitorRefreshBridge` disappear in the same slice if that would widen the blast radius; it can become a thin app-shell wrapper around `CodexMonitorService`.
