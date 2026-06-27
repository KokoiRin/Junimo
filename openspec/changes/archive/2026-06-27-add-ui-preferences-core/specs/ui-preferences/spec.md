## ADDED Requirements

### Requirement: C++ preference snapshot
The system SHALL expose UI preferences from the C++23 core.

#### Scenario: Coordinator starts
- **WHEN** Swift creates the coordinator
- **THEN** it receives accent, density, panel size, and top offset preferences from the C++ bridge

### Requirement: Accent update
The system SHALL update accent preference through the C++23 core.

#### Scenario: User selects accent
- **WHEN** the user selects an accent in the console
- **THEN** Swift updates the C++ preference and reflects the returned accent in visible state

### Requirement: Density update
The system SHALL update density preference through the C++23 core.

#### Scenario: User selects compact density
- **WHEN** the user selects compact density
- **THEN** Swift updates the C++ preference and the expanded panel uses the compact size

### Requirement: No system settings mutation
The first version SHALL NOT mutate macOS system settings for preferences.

#### Scenario: Preference changes
- **WHEN** user changes Junimo preferences
- **THEN** only Junimo in-memory state changes
