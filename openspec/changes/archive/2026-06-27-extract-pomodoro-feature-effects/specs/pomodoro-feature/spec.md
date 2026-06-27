# pomodoro-feature Specification

## ADDED Requirements

### Requirement: Swift Pomodoro Feature Owns Completion Effects

The Swift layer SHALL route Pomodoro lifecycle projection and completion notification effects through a Pomodoro feature owner while keeping portable timer policy in core.

#### Scenario: Feature exposes active timer projection

- **WHEN** Pomodoro starts through the feature
- **THEN** the feature SHALL expose the active Pomodoro projection from core state

#### Scenario: Feature emits completion notification effect

- **GIVEN** an active Pomodoro timer
- **WHEN** time advances before the end
- **THEN** the feature SHALL NOT emit a notification effect
- **WHEN** time advances to the end
- **THEN** the feature SHALL clear the active projection
- **AND** it SHALL emit one Pomodoro completion notification request

#### Scenario: Coordinator remains compatibility projection

- **WHEN** existing UI code calls `TaskCoordinator.startPomodoro` or `TaskCoordinator.advanceTime`
- **THEN** the coordinator SHALL delegate Pomodoro lifecycle work to the feature
- **AND** pending notification requests SHALL still flow through `NotificationOutbox`
