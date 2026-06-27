## ADDED Requirements

### Requirement: Swift uses C++ core for actions
The system SHALL route Swift coordinator action execution through the C++23 core bridge.

#### Scenario: User action runs
- **WHEN** Swift `TaskCoordinator` performs a known action
- **THEN** the result is produced by the C++ core bridge and copied into Swift visible state

### Requirement: Swift uses C++ core for Pomodoro lifecycle
The system SHALL route Pomodoro start, cancel, and completion through the C++23 core bridge.

#### Scenario: Pomodoro completes
- **WHEN** Swift `TaskCoordinator` advances time past the active Pomodoro end time
- **THEN** the completion result is produced by the C++ core bridge and Swift records the notification request

### Requirement: Stable direct build integration
The system SHALL build and link the C++ bridge for direct executable, test, and `.app` scripts.

#### Scenario: Run verification
- **WHEN** the developer runs the verification script
- **THEN** Swift tests, C++ tests, direct build, app bundle build, and OpenSpec validation all pass
