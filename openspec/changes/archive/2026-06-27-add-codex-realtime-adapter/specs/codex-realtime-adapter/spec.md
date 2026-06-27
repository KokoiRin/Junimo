## ADDED Requirements

### Requirement: Codex realtime app-server events
The system SHALL ingest Codex app-server quota and thread notifications in the background.

#### Scenario: Quota notification arrives
- **WHEN** the app-server stream emits a rate-limit notification
- **THEN** Junimo updates the Codex quota display from that event without waiting for the next polling interval

#### Scenario: Thread status notification arrives
- **WHEN** the app-server stream emits a thread status change
- **THEN** Junimo updates the known Codex thread and Codex agent status

### Requirement: Codex exec JSONL events
The system SHALL map Junimo-launched `codex exec --json` lifecycle events into the Codex monitor.

#### Scenario: Exec completes
- **WHEN** an exec JSONL stream reports a started thread and then a completed turn
- **THEN** Junimo marks that Codex thread completed through the same monitor state used by app-server events

#### Scenario: Exec fails
- **WHEN** an exec JSONL stream reports a failed turn or error event
- **THEN** Junimo marks that Codex thread failed through the same monitor state used by app-server events

### Requirement: Terminal Codex alerts
The system SHALL request a notification when a known active Codex thread becomes terminal.

#### Scenario: Active thread completes
- **WHEN** a realtime event changes a known Codex thread from running or waiting to completed
- **THEN** Junimo creates a Codex completion notification and records recent activity

#### Scenario: Active thread fails
- **WHEN** a realtime event changes a known Codex thread from running or waiting to failed
- **THEN** Junimo creates a Codex failure notification and records recent activity

### Requirement: Realtime fallback
The system SHALL keep snapshot polling available when realtime streaming is unavailable.

#### Scenario: Stream unavailable
- **WHEN** the realtime stream cannot start or emits no events
- **THEN** Junimo continues periodic Codex snapshot refreshes and exposes degraded integration findings
