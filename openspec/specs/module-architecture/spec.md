# module-architecture Specification

## Purpose
TBD - created by archiving change define-junimo-module-architecture. Update Purpose after archive.
## Requirements
### Requirement: Feature state has one owner
The system SHALL assign each product feature's mutable business state to exactly one feature owner.

#### Scenario: Codex lifecycle state is updated
- **WHEN** Codex quota, thread lifecycle, or review attention changes
- **THEN** the Codex feature store owns the state transition
- **AND** shell, views, diagnostics, and adapters observe a public projection instead of mutating Codex state directly

#### Scenario: Derived UI text is displayed
- **WHEN** a view needs collapsed Codex status text
- **THEN** it reads a derived projection from the owning feature
- **AND** it does not recompute lifecycle priority from raw adapter data

### Requirement: App shell owns native lifecycle only
The system SHALL keep AppKit lifecycle, panels, status items, and native notification delivery in the app shell layer.

#### Scenario: App starts
- **WHEN** Junimo launches
- **THEN** the app shell creates native windows, panels, menu bar items, and notification delivery hooks
- **AND** feature-specific rules are provided by runtime-composed feature stores

### Requirement: Runtime composition wires features and adapters
The system SHALL use a runtime composition layer to construct feature stores, adapters, schedulers, and diagnostics providers.

#### Scenario: A background monitor starts
- **WHEN** a feature needs a long-running external monitor
- **THEN** runtime composition starts the adapter or monitor service
- **AND** the feature receives typed events rather than owning the external process directly

### Requirement: Adapters own external I/O only
The system SHALL keep external process, filesystem, OS, notification, and protocol I/O inside adapter components.

#### Scenario: Codex app-server stream fails
- **WHEN** the Codex app-server stream cannot start or ends unexpectedly
- **THEN** the adapter reports a typed degraded result or event
- **AND** it does not directly mutate UI state, review attention, or health snapshots

### Requirement: Feature stores expose testable contracts
The system SHALL make each feature store testable through public intents, events, state projections, effects, and snapshots.

#### Scenario: A feature rule is added
- **WHEN** Junimo adds or changes a feature state rule
- **THEN** the rule can be covered by a unit test at the feature store or domain policy layer
- **AND** the test does not require launching the macOS app

### Requirement: Diagnostics compose public snapshots
The system SHALL build health and harness diagnostics from public feature snapshots.

#### Scenario: Launch health is written
- **WHEN** Junimo writes its launch health snapshot
- **THEN** diagnostics read public feature snapshots
- **AND** diagnostics do not become a second authority for feature state

### Requirement: Compatibility coordinator remains temporary
The system SHALL keep the existing coordinator as a compatibility facade during migration.

#### Scenario: A feature is extracted
- **WHEN** behavior moves from `TaskCoordinator` into a feature store
- **THEN** `TaskCoordinator` delegates to the feature store for that behavior
- **AND** new business rules are not duplicated inside the coordinator

