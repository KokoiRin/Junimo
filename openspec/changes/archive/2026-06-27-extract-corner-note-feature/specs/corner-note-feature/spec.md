# corner-note-feature Specification

## ADDED Requirements

### Requirement: Corner Note has a feature owner
The system SHALL route Corner Note expansion, note text, and todo projection through a Corner Note feature owner.

#### Scenario: User edits Corner Note content
- **WHEN** the user updates note text or modifies todos
- **THEN** `CornerNoteFeature` updates its public snapshot from `CornerNoteCore`
- **AND** `TaskCoordinator` exposes that snapshot as a compatibility projection

### Requirement: Expansion is independent from content
The system SHALL keep Corner Note expanded/collapsed state independent from note and todo content.

#### Scenario: User collapses the Corner Note
- **WHEN** the user collapses the Corner Note panel
- **THEN** note text and todo content remain unchanged
