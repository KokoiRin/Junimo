# Define Junimo Module Architecture

## Why

Junimo has enough product surface to need deeper module boundaries before the next round of feature work. The current app can show the island, quota, Pomodoro, todos, and notes, but Codex lifecycle bugs show that key state is spread across UI-facing coordinator code, protocol adapters, parsers, diagnostics, and views.

The main symptom is not one missing refresh. `TaskCoordinator` is acting as UI facade, feature store, Codex lifecycle reducer, command dispatcher, Pomodoro owner, Corner Note owner, notification queue, and diagnostics source. `CodexStatusProvider.swift` also combines process management, app-server JSON-RPC, realtime streaming, exec streaming, parsing, and snapshot composition. That shape made early slices fast, but it makes later behavior hard to reason about and hard to test at the right level.

## What Changes

- Define a target module structure for Junimo's app shell, runtime composition, feature stores, adapters, domain policy, and diagnostics.
- Establish component contracts for state ownership, intent/event flow, side effects, and test surfaces.
- Keep `TaskCoordinator` as a temporary compatibility facade while feature stores are extracted behind it.
- Choose Codex as the first pilot extraction because its lifecycle, quota, completion attention, and external protocol seams expose the current design pressure.
- Align the test pyramid with the module structure: pure reducers and parsers at the bottom, fake-backed adapter integration tests in the middle, and small launch/health scenarios at the top.

## Non-Goals

- Do not rewrite the UI in this change.
- Do not rewrite the C++ core or move Codex protocol behavior into C++ now.
- Do not introduce a generic plugin or adapter registry before a second real adapter needs it.
- Do not implement the full refactor in this design change; implementation should happen in follow-up TDD slices.
