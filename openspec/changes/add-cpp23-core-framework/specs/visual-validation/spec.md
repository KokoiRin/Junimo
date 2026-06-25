## ADDED Requirements

### Requirement: Unlocked desktop validation
The system SHALL treat visual desktop validation as valid only when the macOS user session is unlocked.

#### Scenario: App starts in unlocked session
- **WHEN** Junimo is launched while the desktop is unlocked
- **THEN** screenshot or direct UI interaction can be used to validate capsule, hover, and click behavior

#### Scenario: Session is locked
- **WHEN** screenshot verification sees the macOS lock screen
- **THEN** visual validation is recorded as blocked rather than treated as proof of UI failure
