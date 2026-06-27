# launch-health-snapshot Specification

## Purpose
Define local launch diagnostics that prove the app initialized its panel and core-backed state in automated checks.
## Requirements
### Requirement: Launch health JSON
The system SHALL write a local JSON health snapshot after app launch initializes the panel.

#### Scenario: App launches
- **WHEN** Junimo launches successfully
- **THEN** it writes a JSON health file containing process, panel, preferences, and core-backed state counts

### Requirement: Health validation script
The system SHALL provide a script that validates the launch health snapshot.

#### Scenario: Verify launch health
- **WHEN** the developer runs the health validation script
- **THEN** the script launches the app bundle and verifies the JSON reports a visible panel and non-empty core-backed state

### Requirement: Local-only diagnostics
The health snapshot SHALL remain local and SHALL NOT transmit data.

#### Scenario: Health snapshot writes
- **WHEN** the health snapshot is generated
- **THEN** it is written only to a local file path
