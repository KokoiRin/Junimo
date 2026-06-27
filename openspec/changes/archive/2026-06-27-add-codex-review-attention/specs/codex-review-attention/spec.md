## ADDED Requirements

### Requirement: Codex review items
The system SHALL create a pending review item when a known active Codex thread becomes completed or failed.

#### Scenario: Active thread completes
- **WHEN** a Codex thread changes from running or waiting to completed
- **THEN** Junimo records a pending review item for that thread

#### Scenario: Active thread fails
- **WHEN** a Codex thread changes from running or waiting to failed
- **THEN** Junimo records a pending review item for that thread

### Requirement: Persistent attention
The system SHALL keep Codex review attention visible until the user acknowledges it.

#### Scenario: Notification delivered
- **WHEN** a Codex completion notification request is delivered or removed from the delivery queue
- **THEN** the pending Codex review item remains visible

#### Scenario: User acknowledges review
- **WHEN** the user marks a Codex review item handled
- **THEN** Junimo removes that review item and clears the persistent attention state when no review items remain

### Requirement: Island review cue
The system SHALL show a clear island cue while Codex review items are pending.

#### Scenario: Island collapsed
- **WHEN** there are pending Codex review items and the island is collapsed
- **THEN** the collapsed island shows an attention cue and count

#### Scenario: Island expanded
- **WHEN** there are pending Codex review items and the island is expanded
- **THEN** the island shows the latest Codex result and provides an acknowledgement action
