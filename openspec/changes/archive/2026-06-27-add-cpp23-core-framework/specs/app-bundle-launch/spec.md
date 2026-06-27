## ADDED Requirements

### Requirement: App bundle build
The system SHALL provide a script that builds Junimo as a macOS `.app` bundle.

#### Scenario: Build app bundle
- **WHEN** the developer runs the app bundle build script
- **THEN** a `Junimo.app` bundle exists with an executable and required local dynamic libraries

### Requirement: App bundle launch
The system SHALL provide a script that launches the app bundle through macOS.

#### Scenario: Launch app bundle
- **WHEN** the developer runs the app launch script
- **THEN** macOS starts Junimo as an app process without requiring SwiftPM

### Requirement: Visual validation note
The documentation SHALL state that desktop visual validation requires an unlocked user session.

#### Scenario: Desktop is locked
- **WHEN** screenshot verification sees the macOS lock screen
- **THEN** the progress documentation records that visual hover/click validation is blocked until unlock
