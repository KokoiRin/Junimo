# self-update Specification

## Purpose
Define how an installed Junimo app checks GitHub Release versions, exposes an update button, and starts an external updater only after the user chooses that button.

## Requirements
### Requirement: Update availability checks
Junimo SHALL let the user check the latest GitHub Release version from the status menu, and MAY also check once after launch, without installing anything automatically.

#### Scenario: Newer release is discovered
- **GIVEN** the running Junimo bundle version is `0.1.4`
- **AND** the latest GitHub Release tag is `v0.1.5`
- **WHEN** an update check completes
- **THEN** Junimo SHALL record an available update for version `0.1.5`
- **AND** the status menu SHALL expose an update action
- **AND** Junimo SHALL NOT install the update until the user chooses that update action

#### Scenario: No newer release exists
- **GIVEN** the running Junimo bundle version is `0.1.5`
- **AND** the latest GitHub Release tag is `v0.1.5`
- **WHEN** an update check completes
- **THEN** Junimo SHALL record that the app is up to date
- **AND** the status menu SHALL NOT present an install action

#### Scenario: Check fails
- **WHEN** an update check cannot fetch or parse the latest release
- **THEN** Junimo SHALL record a check failure
- **AND** Junimo SHALL NOT show a blocking modal
- **AND** Junimo SHALL NOT start the installer

### Requirement: Manual update check
Junimo SHALL let the user manually check for updates from the status menu and show a result for that check.

#### Scenario: User checks and no update is available
- **GIVEN** the latest release version is not newer than the current bundle version
- **WHEN** the user chooses `Check for Updates...`
- **THEN** Junimo SHALL perform a fresh update check
- **AND** Junimo SHALL tell the user that Junimo is up to date

#### Scenario: User checks and an update is available
- **GIVEN** the latest release version is newer than the current bundle version
- **WHEN** the user chooses `Check for Updates...`
- **THEN** Junimo SHALL expose an `Install Update...` action in the status menu
- **AND** Junimo SHALL NOT start the installer until the user chooses `Install Update...`

#### Scenario: Manual check fails
- **WHEN** the user chooses `Check for Updates...`
- **AND** the release check fails
- **THEN** Junimo SHALL show a failure message
- **AND** Junimo SHALL leave the app running
- **AND** Junimo SHALL NOT start the installer

### Requirement: Button-triggered update installation
Junimo SHALL install a newer release only after the user chooses the update action.

#### Scenario: User clicks available update
- **GIVEN** Junimo has recorded an available update
- **WHEN** the user chooses `Install Update...`
- **THEN** Junimo SHALL start an external updater for the current app install directory
- **AND** Junimo SHALL transition its update state to installing
- **AND** the current app process MAY quit so the external updater can replace the app bundle

#### Scenario: Installer cannot start
- **GIVEN** Junimo has recorded an available update
- **WHEN** the user chooses `Install Update...`
- **AND** the external updater cannot be started
- **THEN** Junimo SHALL record an installation failure
- **AND** Junimo SHALL leave the current app running

### Requirement: Version comparison boundary
Junimo SHALL compare release tags against the current bundle version before presenting an install action.

#### Scenario: Release tag has v prefix
- **GIVEN** the current bundle version is `0.1.4`
- **WHEN** the release checker returns tag `v0.1.5`
- **THEN** Junimo SHALL compare it as version `0.1.5`

#### Scenario: Release tag is not parseable
- **WHEN** the release checker returns a tag that cannot be parsed as a stable version
- **THEN** Junimo SHALL record a check failure
- **AND** Junimo SHALL NOT present an install action
