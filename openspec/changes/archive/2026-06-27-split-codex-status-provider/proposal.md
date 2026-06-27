# Split Codex Status Provider Boundaries

## Why

`CodexStatusProvider.swift` has become a vertical pile of unrelated layers: public contracts, process execution, app-server JSON-RPC query, realtime app-server stream, `codex exec --json` stream, snapshot provider, snapshot parser, and realtime parser. That shape blocks the next product step, because launching real Codex work from the island will need a clear place to attach process I/O, typed lifecycle events, and test fixtures.

Junimo now has `CodexFeature` as the state owner. The next boundary to clean is the Codex adapter side: external I/O should stay in adapters/transports, parsers should be pure, and monitor/provider composition should only combine typed results before handing them to the feature or compatibility coordinator.

## What Changes

- Split Codex contracts, process transports, app-server query, realtime streams, snapshot provider, snapshot parser, and realtime parser into separate source files.
- Preserve current public API and UI behavior while reducing the file-level coupling.
- Add a small monitor-service boundary for applying snapshot and realtime events to a sink, so future runtime composition can connect adapters to `CodexFeature` without going through parser internals.
- Keep existing direct smoke tests and app bridge tests as the public behavior safety net.

## Non-Goals

- Do not implement the island prompt/workspace launch flow in this change.
- Do not introduce a generic adapter registry yet.
- Do not move Codex protocol behavior into C++.
- Do not change visible Codex status semantics unless tests expose an existing inconsistency.
