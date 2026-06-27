## ADDED Requirements

### Requirement: Runtime owns software update lifecycle
The app shell SHALL use runtime composition to own self-update service lifecycle while keeping AppDelegate focused on AppKit menu and alert presentation.

#### Scenario: Runtime starts update checking
- **GIVEN** the macOS app is launching
- **WHEN** AppDelegate creates and starts Junimo runtime
- **THEN** the runtime SHALL start the software update service
- **AND** AppDelegate SHALL NOT directly fetch GitHub release metadata

#### Scenario: Runtime stops update checking
- **GIVEN** the runtime has started the software update service
- **WHEN** the app terminates runtime
- **THEN** the runtime SHALL stop the software update service
- **AND** stopped update checks SHALL NOT mutate coordinator state afterward

#### Scenario: AppDelegate requests user-initiated update check
- **WHEN** the user chooses `Check for Updates...` from the status menu
- **THEN** AppDelegate SHALL delegate the update check intent to runtime or coordinator
- **AND** AppDelegate SHALL NOT compare release versions itself
- **AND** AppDelegate SHALL NOT directly run the updater without an available-update state
