## ADDED Requirements

### Requirement: C++ core command catalog
The system SHALL define command entries in the C++23 core.

#### Scenario: Core starts
- **WHEN** a C++ core engine is created
- **THEN** it exposes command entries for agent, project, tools, and Pomodoro workflows

### Requirement: Command search
The system SHALL filter commands by query in the C++23 core.

#### Scenario: User searches commands
- **WHEN** the user types a query in the command palette
- **THEN** Swift receives C++ filtered command snapshots whose title, subtitle, category, or tags match the query

### Requirement: Command launch
The system SHALL launch a command through the existing coordinator action path.

#### Scenario: User clicks a command
- **WHEN** the user clicks a command result
- **THEN** the coordinator performs the command action id through the C++ backed execution path
