## ADDED Requirements

### Requirement: Create Pomodoro session
The system SHALL allow the user to create a Pomodoro session from the console.

#### Scenario: User starts a Pomodoro
- **WHEN** the user starts a Pomodoro session
- **THEN** the system records an active timer with a start time, duration, and projected end time

### Requirement: Cancel Pomodoro session
The system SHALL allow the user to cancel an active Pomodoro session.

#### Scenario: User cancels active Pomodoro
- **WHEN** the user cancels the active Pomodoro
- **THEN** the system clears the active timer and records a cancellation activity

### Requirement: Complete Pomodoro session
The system SHALL mark a Pomodoro session as complete when its duration has elapsed.

#### Scenario: Timer reaches end time
- **WHEN** the active Pomodoro reaches its end time
- **THEN** the system clears the active timer, records completion, and creates a notification request

### Requirement: Completion reminder boundary
The first version SHALL expose Pomodoro completion as a notification request from core logic instead of embedding system notification permission flow in the UI.

#### Scenario: Pomodoro completes
- **WHEN** a Pomodoro completion is detected
- **THEN** the core layer exposes the reminder request for a future notification adapter to deliver
