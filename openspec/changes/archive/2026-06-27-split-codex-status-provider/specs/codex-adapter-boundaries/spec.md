# codex-adapter-boundaries Specification

## ADDED Requirements

### Requirement: Codex external I/O stays in adapters
The system SHALL keep Codex process execution, app-server stdio, realtime stream reads, and exec stream reads inside adapter or transport components.

#### Scenario: Snapshot provider reads Codex state
- **WHEN** Junimo refreshes Codex quota and thread state
- **THEN** process execution happens through Codex adapter contracts
- **AND** provider composition receives typed command/query results instead of mutating feature state directly

### Requirement: Codex parsers are pure protocol translators
The system SHALL keep Codex snapshot and realtime parsers free of process I/O and feature-state mutation.

#### Scenario: App-server notification is parsed
- **WHEN** a raw app-server notification JSON line is parsed
- **THEN** the parser returns a typed `CodexRealtimeEvent`
- **AND** it does not update `TaskCoordinator`, `CodexFeature`, health snapshots, or notification queues

### Requirement: Codex monitor service delivers typed observations
The system SHALL expose a monitor service boundary that delivers provider snapshots, realtime events, and integration findings to a typed sink.

#### Scenario: Realtime stream reports a degraded finding
- **WHEN** the Codex realtime stream finishes with a degraded integration finding
- **THEN** the monitor service delivers that finding to its sink as a typed observation
- **AND** the stream does not directly mutate UI or feature state

### Requirement: Compatibility bridge delegates to monitor boundary
The system SHALL keep app-shell bridge behavior compatible while delegating Codex monitoring work to the monitor boundary.

#### Scenario: App bridge starts
- **WHEN** the current app bridge starts Codex monitoring
- **THEN** it starts the monitor service or equivalent boundary
- **AND** existing fake-backed bridge tests continue to pass without launching a real Codex process
