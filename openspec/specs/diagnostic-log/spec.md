# diagnostic-log Specification

## Purpose
Define Junimo's in-app diagnostic log timeline and main panel log surface.

## Requirements

### Requirement: In-app diagnostic log timeline

Junimo SHALL keep a bounded in-memory diagnostic log timeline for app-owned behavior and feature state changes.

#### Scenario: User behavior is recorded

- **WHEN** the user triggers a supported panel or feature action
- **THEN** Junimo SHALL append a diagnostic log entry with timestamp, level, source, title, and detail
- **AND** the newest log entry SHALL appear first

#### Scenario: Log timeline is bounded

- **WHEN** more log entries are recorded than the configured limit
- **THEN** Junimo SHALL keep the newest entries and discard older entries

### Requirement: Main panel log page

The expanded main panel SHALL expose a Logs page in the module navigation.

#### Scenario: User views logs

- **WHEN** the user selects the Logs page
- **THEN** Junimo SHALL show recent diagnostic log entries and the latest log summary

#### Scenario: User writes a debug probe

- **WHEN** the user clicks the debug probe action on the Logs page
- **THEN** Junimo SHALL record a debug-level log entry from the Debug source
- **AND** the action SHALL NOT request screenshot, notification, shell, or network permissions

### Requirement: Main panel readable text

The expanded main panel SHALL use larger primary text than the previous compact information layout.

#### Scenario: Panel renders module content

- **WHEN** the expanded panel renders module page content
- **THEN** primary labels and values SHALL use the shared readable type scale
