## ADDED Requirements

### Requirement: Collapsed completion cue
The system SHALL prioritize pending Codex completion or failure results in the collapsed island status slot.

#### Scenario: Completed result pending
- **WHEN** a known Codex thread completes and a review item is pending
- **THEN** the collapsed island status slot shows a completed Codex cue instead of passive quota text

#### Scenario: Failed result pending
- **WHEN** a known Codex thread fails and a review item is pending
- **THEN** the collapsed island status slot shows a failed Codex cue instead of passive quota text

#### Scenario: No review pending
- **WHEN** there are no pending Codex review items
- **THEN** the collapsed island status slot shows Codex quota summary text
