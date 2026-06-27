# Design: Junimo Module Architecture

## Target Type

[P0][架构预备]

## Core Behavior Semantics

当后续功能需要读取或改变产品状态时，系统应该通过明确的 feature store、adapter、domain policy 和 diagnostics 契约流动，而不是让 UI coordinator 同时拥有业务状态、外部协议、副作用和健康快照。

## Current Diagnosis

The current shape has served the prototype phase, but it is now too shallow for the next product depth:

- `TaskCoordinator` has too many reasons to change: console expansion, command search, Codex monitor and review attention, Pomodoro, notifications, Corner Note, preferences, C++ bridge refresh, and launch diagnostics.
- `CodexStatusProvider.swift` contains multiple different layers in one file: command runner, app-server client, realtime stream, exec stream, provider, parser, and protocol-to-domain mapping.
- `JunimoModels.swift` is a shared model bucket, so feature concepts do not have a clear home.
- `AppDelegate` wires concrete product objects directly and launch health reads broad coordinator state, which encourages diagnostics to depend on whichever fields are currently public.
- The C++ core boundary is useful for stable portable state, but Swift still lacks feature-module boundaries around native and external integrations.

## Target Modules

### `Junimo` App Shell

- Responsibility: owns AppKit lifecycle, panels, status item, native notification delivery, and SwiftUI hosting.
- Not responsible for: product lifecycle rules, Codex protocol state, Pomodoro policy, Corner Note persistence policy, or diagnostics interpretation.
- Test surface: launch health and functional scenario checks prove wiring, not business rules.

### Runtime Composition

- Responsibility: constructs feature stores, adapters, schedulers, and diagnostics providers; owns startup order and cancellation.
- Not responsible for: feature-specific decisions.
- State: references to feature stores and long-lived services only.
- Side effects: starts timers/streams and tears them down.
- Test surface: fake-backed integration tests can prove startup starts the expected monitor/stream without launching the full app.

### Feature Stores

Feature stores own state and expose a small intent/event surface. Initial feature modules:

- `ConsoleFeature`: island expansion, command palette projection, density/accent projection, and high-level surface state.
- `CodexFeature`: quota display, known thread lifecycle, review attention, completion acknowledgement, and Codex status priority.
- `PomodoroFeature`: focus session lifecycle and notification requests.
- `CornerNoteFeature`: quick note text and todo list state.
- `SessionsFeature`: execution timeline and activity projection.

Each feature store should have:

- `State`: the single authority for feature-owned state.
- `Intent`: user or runtime requests.
- `Event`: adapter/domain observations.
- `Effect`: typed side effects requested by the feature, executed by runtime/adapters.
- `Snapshot`: public diagnostics/test projection.

### Adapters

- Responsibility: own external process, filesystem, OS, notification, and protocol I/O.
- Not responsible for: product state priority, review attention policy, UI text priority, or lifecycle decisions beyond protocol normalization.
- Initial adapters: Codex app-server transport, Codex CLI/exec transport, user notification delivery, native panel/status-item shell, and persistence adapters.
- Test surface: fake transports and fixture-backed parser tests; no real Codex process is required for unit tests.

### Domain Policy

- Responsibility: pure reducers, ordering rules, value objects, and portable state transitions.
- Placement: Swift domain for moving/native protocol rules; C++ core for stable portable policies that are not tied to macOS or Codex protocol details.
- Not responsible for: starting processes, reading files, writing health snapshots, or presenting UI.
- Test surface: fast unit tests over reducers, parsers, and policies.

### Diagnostics

- Responsibility: compose public feature snapshots into launch health and Chowa harness evidence.
- Not responsible for: reaching through feature internals or becoming a second state authority.
- Test surface: snapshot serialization tests and app launch health checks.

## Dependency Direction

```text
Junimo App Shell
        ↓
Runtime Composition
        ↓
Feature Stores
        ↓
Domain Policy

Runtime Composition → Adapters
Adapters → typed Events / Results → Feature Stores
Diagnostics → public Feature Snapshots
```

Views render state and dispatch intents. They do not know process protocols. Adapters perform I/O and emit typed observations. Reducers decide what the observations mean for product state.

## Component Contracts

### Component Contract: Feature Store

- Responsibility: own one feature's state, reduce intents/events, and request typed effects.
- Not responsible for: executing process I/O, owning AppKit objects, or formatting all UI layout.
- Owner: the feature module.
- Interface: `send(intent:)`, `receive(event:)`, public state/snapshot projection, and effect output.
- State: one state owner per feature; derived state documents its source.
- Side effects: represented as effects and executed outside the store.
- Invariants: no feature state is mutated by another feature; terminal events are explicit; acknowledgement is an intent, not an incidental notification side effect.
- Lifecycle: constructed by runtime, disposed by runtime.
- Test surface: reducer/store tests through public intents, events, state, effects, and snapshots.

### Component Contract: Adapter

- Responsibility: translate external protocols and OS services into typed events/results.
- Not responsible for: UI priority, product review attention, or cross-feature orchestration.
- Owner: runtime composition.
- Interface: start/stop/query APIs returning typed results or streaming typed events.
- State: only connection/process/session state needed for I/O.
- Side effects: external process, filesystem, notification, app-server, and OS interactions.
- Invariants: adapter failure is reported as a typed degraded event/result; failure must not mutate feature state directly.
- Lifecycle: runtime starts, cancels, and tears down adapters.
- Test surface: fake transport tests and fixture parser tests.

### Component Contract: Compatibility Coordinator

- Responsibility: temporarily project feature state to existing SwiftUI views and preserve current public API while migration proceeds.
- Not responsible for: owning new feature business logic.
- Owner: runtime/UI compatibility layer.
- Interface: existing `TaskCoordinator` properties and methods during migration.
- State: only projections or delegated state; no new long-lived product authority.
- Side effects: delegates to runtime/features/adapters.
- Invariants: any newly extracted feature rule must live in the feature module, not be reimplemented in the coordinator.
- Lifecycle: removed or thinned after views bind to feature stores.
- Test surface: compatibility tests only for projection behavior; core behavior lives in feature tests.

## First Walking Skeleton

The first implementation slice should extract Codex because it is the feature currently showing structural stress.

1. Introduce a `CodexFeature` boundary with state, intent, event, effect, snapshot, and reducer tests.
2. Move normalized lifecycle priority, review attention, acknowledgement, and collapsed status priority into `CodexFeature`.
3. Split Codex external integration into transport/client/parser/provider pieces:
   - transport/process I/O
   - app-server query and realtime stream
   - exec JSONL stream
   - parser/normalizer
   - monitor service that emits `CodexFeature.Event`
4. Keep `TaskCoordinator` delegating to the feature so existing views continue to work.
5. Make launch health read a `CodexFeature.Snapshot` rather than broad coordinator internals.

This skeleton has real call paths and tests. It is not an empty folder split.

## Test Pyramid Alignment

- Unit tests: feature reducers, pure lifecycle policies, parsers, and C++ core policies.
- Integration tests: runtime wiring with fake adapters, Codex monitor service with fake transports, Swift-to-C++ bridge smoke.
- End-to-end tests: app launch health and one or two functional scenarios that prove the shell can start and expose snapshots.

## Current Non-Decisions

- Do not create separate SwiftPM targets immediately if the local SwiftPM manifest issue still blocks normal `swift test`. Start with folders/namespaces and move to targets after the package workflow is healthy.
- Do not move Codex lifecycle into C++ now. Codex protocol behavior is moving, local, and platform/tool coupled.
- Do not build a generic adapter registry yet. Name the Codex boundary first; generalize only after another real adapter proves the same contract.

## Migration Order

1. Document architecture and requirements.
2. Extract Codex feature store and tests while keeping UI behavior stable.
3. Split Codex provider internals behind fakeable transports and parser fixtures.
4. Move diagnostics to public feature snapshots.
5. Extract Pomodoro and Corner Note after Codex proves the pattern.
6. Revisit package targets and adapter registry after the shape has two or more real modules.
