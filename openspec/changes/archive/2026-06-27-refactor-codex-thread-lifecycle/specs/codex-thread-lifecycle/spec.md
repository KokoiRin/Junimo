## ADDED Requirements

### Requirement: Normalized Codex thread lifecycle
The system SHALL normalize Codex source observations into explicit thread lifecycle states before computing UI status.

#### Scenario: App-server active thread
- **WHEN** app-server `thread/list` or realtime events report a thread with `status.type` of `active`
- **THEN** Junimo marks that thread running when no waiting flags are present
- **AND** Junimo marks that thread waiting when waiting flags are present

#### Scenario: App-server not loaded thread
- **WHEN** app-server reports a non-archived thread with `status.type` of `notLoaded`
- **THEN** Junimo marks that thread open rather than completed, failed, or idle quota-only state

#### Scenario: Unknown app-server status
- **WHEN** app-server reports an unknown non-terminal status
- **THEN** Junimo keeps the thread visible as open or degraded instead of treating it as completed

### Requirement: Explicit terminal transitions
The system SHALL create Codex completion or failure review items only from explicit terminal lifecycle transitions.

#### Scenario: Explicit completion
- **WHEN** a known running, waiting, or open Codex thread receives an explicit completed terminal event
- **THEN** Junimo records a pending completion review item for that thread

#### Scenario: Explicit failure
- **WHEN** a known running, waiting, or open Codex thread receives an explicit failed terminal event
- **THEN** Junimo records a pending failure review item for that thread

#### Scenario: Snapshot omits active thread
- **WHEN** a later snapshot omits a previously active Codex thread
- **THEN** Junimo does not create a completion review from the omission alone

### Requirement: Open work display priority
The system SHALL keep Codex open-work state visible before falling back to quota text.

#### Scenario: No review and no active thread but open work remains
- **WHEN** there are no pending review items and no running or waiting threads
- **AND** at least one non-terminal open Codex thread remains
- **THEN** the collapsed island status shows an open-work cue instead of quota text

#### Scenario: No Codex work remains
- **WHEN** there are no pending review items, no running or waiting threads, and no open Codex threads
- **THEN** the collapsed island status shows Codex quota summary text

### Requirement: Lifecycle-aware thread truncation
The system SHALL compute lifecycle counts and status priority before truncating the visible thread list.

#### Scenario: Older active or open thread exists beyond recent display limit
- **WHEN** a Codex source returns more threads than the visible UI list can show
- **AND** an active or open thread appears beyond the visible limit by update time
- **THEN** Junimo still includes that thread in active/open counts and collapsed status priority
