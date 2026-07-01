# Architecture Notes

## Current Boundary

Junimo has three layers:

1. `Sources/Junimo`: macOS shell. Owns `NSApplication`, `NSPanel`, SwiftUI layout, hover events, and system notification delivery.
2. `Sources/JunimoCore`: Swift observable shell used by the current UI. It owns UI-ready snapshots and calls the C++ bridge for action and Pomodoro behavior.
3. `Core`: C++23 portable core. Owns the long-term domain model for agents, actions, activities, and Pomodoro lifecycle. `Core/include/junimo/core/c_api.h` exposes a narrow C ABI bridge consumed from Swift.

Swift/AppKit should remain responsible for native desktop behavior. C++ should own portable policy and state transitions.

## Target Module Structure

Junimo should grow from the current three-layer prototype into a set of deeper
modules with explicit state owners and test seams:

1. `Junimo` app shell: owns `NSApplication`, panels, menu bar status item,
   SwiftUI hosting, native notification delivery, and quit/show commands.
2. Runtime composition: constructs feature stores, adapters, schedulers, and
   diagnostics providers; owns startup order and teardown. `JunimoRuntime` is
   the current app-layer composition point for `TaskCoordinator`, reminder
   delivery, Codex monitoring, and launch health diagnostics.
3. Feature stores: own product state, reduce user intents and adapter events,
   and expose public snapshots. Initial feature boundaries are Console, Codex,
   Pomodoro, Corner Note, Preferences, and Sessions. Console, Codex, Pomodoro,
   Corner Note, and Preferences already have explicit Swift feature owners
   behind the coordinator compatibility facade.
4. Adapters: own process, filesystem, OS, notification, and protocol I/O. Codex
   app-server, Codex CLI/exec streams, notification delivery, and persistence
   belong here.
5. Domain policy: pure reducers, ordering rules, value objects, parsers, and
   portable transitions. Stable portable policies can move into `Core`; moving
   native or fast-changing protocol behavior into C++ is not required.
6. Shared effect stores: own cross-feature pending effects such as system
   notification requests without owning feature-specific decisions.
7. Diagnostics: composes public feature snapshots into launch health and harness
   evidence without becoming another state authority.

Dependency direction should stay simple:

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

The practical rule is: views dispatch intents and render state; adapters do I/O
and emit typed observations; reducers decide what observations mean for product
state.

## Runtime Composition

`Sources/Junimo/JunimoRuntime.swift` is the app-layer owner for startup wiring
that is not itself AppKit surface code:

1. It exposes the shared `TaskCoordinator` used by panel controllers.
2. It starts `ReminderDeliveryBridge` so pending notification requests from
   feature stores flow to platform notification delivery.
3. It starts `CodexMonitorRefreshBridge` with injectable provider/stream seams
   so snapshot fallback and realtime findings enter the coordinator through the
   same typed monitor sink.
4. It owns launch health reporting and the functional health scenario entry.

`AppDelegate` should remain responsible for `NSApplication`, panels, status
item menu commands, and panel diagnostics. New app-level bridge wiring should
prefer `JunimoRuntime`; new UI surface wiring should remain in the app shell.

## State Ownership Rules

- A feature has exactly one mutable business-state owner.
- Derived UI text is computed by the owning feature or its public projection, not
  independently by multiple views.
- External process and protocol failures are adapter outputs, not direct UI
  mutations.
- Launch health and Chowa harness checks read public snapshots from feature
  stores.
- `TaskCoordinator` remains a temporary compatibility facade while existing
  SwiftUI views migrate. New feature rules should be delegated to feature
  modules rather than reimplemented in the coordinator.

## Codex Walking Skeleton

Codex is the first feature extraction because it already combines quota,
thread lifecycle, review attention, collapsed status priority, app-server
snapshots, realtime events, exec JSONL, notifications, and launch diagnostics.

Current slice:

1. `CodexFeature` owns Codex monitor state, review attention, collapsed status
   priority, agent projection, and terminal notification/activity effects.
2. `TaskCoordinator` remains the compatibility facade for existing SwiftUI
   views, but Codex state mutations delegate to `CodexFeature`.
3. Launch health reads `CodexFeatureSnapshot` instead of reconstructing Codex
   diagnostics from scattered coordinator fields.
4. Direct smoke tests exercise the feature boundary and the compatibility
   coordinator path.
5. Codex adapter boundaries are split by responsibility:
   `CodexAdapterContracts`, `CodexProcessRunner`, `CodexAppServerClient`,
   `CodexRealtimeStreams`, `CodexStatusParser`, `CodexRealtimeEventParser`, and
   `CodexMonitorService`.

Remaining Codex extraction work:

1. Move expanded UI Codex projections behind feature snapshots as the SwiftUI
   surface migrates away from the compatibility coordinator.
2. Revisit a generic adapter registry only after another real adapter shares the
   same lifecycle and action contract.

## Launch Diagnostics

The app writes a local health snapshot at `/tmp/junimo-health.json` after the AppKit panel is shown. This is local-only diagnostic evidence for automated checks and contains process, panel, and C++ core-backed coordinator state. It is not telemetry and is not uploaded.

## Notch And Menu Bar Boundary

Junimo requests a top-center floating `NSPanel` position using the full screen frame. macOS can still clamp normal app windows/panels below the menu bar and camera notch reserved area. That means a floating capsule can sit at the highest system-allowed edge, but it cannot reliably occupy the actual menu bar/notch area through public AppKit panel APIs.

For real menu bar presence, Junimo also installs an `NSStatusItem` with Show and Quit commands. A status item is system-positioned in the menu bar rather than freely centered under the notch.

## Main Panel Surface

The expanded panel is a Chinese module surface instead of a single dense
dashboard. `JunimoSurfaceView` owns only presentation state for the selected
page; feature state still comes from `TaskCoordinator` projections. The current
tabs are Codex, Focus, Note, and Screenshot. This keeps each module readable and
prevents detached capabilities, such as the background screenshot script, from
looking like app-owned controls.

Visible labels are centralized in `JunimoSurfaceCopy.simplifiedChinese`. Future
language switching should add another copy bundle or locale selector rather
than scattering string literals through the SwiftUI layout.

## Next Feature Scale

The tool should grow through feature modules and adapters:

- Codex feature: reliable lifecycle, quota, review attention, animated attention cues, and diagnostics through one state owner.
- Corner Note feature: expanded state, note text projection, todo projection,
  and `CornerNoteCore` persistence mutations through one state owner.
- Notification outbox: pending system notification requests from Codex,
  Pomodoro, and future features through one queue owner; app shell delivery
  remains in `ReminderDelivery`.
- Pomodoro feature: focus/break modes, completion actions, and project/session association.
- Project profiles: per-repository shortcuts, recent tasks, preferred agents, and safe working directories.
- Command palette: searchable actions that can be triggered from the expanded console and routed as intents.
- Session timeline: richer activity entries with status, duration, adapter, and failure reason.
- Theme profiles: compact density, accent, material strength, and notch offset.
- Adapter registry: only after at least two real adapters share the same stable contract.

## Swift To C++ Bridge

The current app uses a narrow C ABI bridge instead of exposing C++ containers directly to Swift UI.

Current path:

1. Keep `junimo::core::TaskEngine` as the C++ owner of domain state.
2. Expose `JunimoCoreEngineRef` and small result structs from `c_api.h`.
3. Call the bridge from `Sources/JunimoCore/CppCoreBridge.swift` through `@_silgen_name`.
4. Map bridge snapshots into Swift `ObservableObject` state in `TaskCoordinator`.
5. Current bridge-backed behavior:
   - agent and action catalog snapshots
   - recent activity feed snapshots and trimming
   - active Pomodoro snapshot
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

- Add session cancellation/retry policies once real adapters report lifecycle events.
- Persist C++ UI preferences to a user config file after the in-memory model settles.
- Replace thread-local string snapshots with owned buffers if asynchronous bridge calls become necessary.
- Add adapter registry policy to C++ while keeping actual system execution in platform adapters.
