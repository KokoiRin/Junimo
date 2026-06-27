# session-timeline Specification

## Purpose
Define C++-backed execution session records and the session timeline visible in the expanded console.
## Requirements
### Requirement: C++ execution sessions
The system SHALL create execution session records in the C++23 core when supported workflows start.

#### Scenario: Agent action starts
- **WHEN** the user starts an agent action
- **THEN** the C++ core records a running session for that action

#### Scenario: Project action completes
- **WHEN** the user starts a mock project action
- **THEN** the C++ core records a succeeded session for that action

### Requirement: Session snapshots
The system SHALL expose recent execution sessions through the C ABI bridge.

#### Scenario: Swift refreshes sessions
- **WHEN** Swift asks the bridge for recent sessions
- **THEN** Swift receives bounded session snapshots with title, detail, status, and start time

### Requirement: Session timeline UI
The expanded console SHALL show recent execution sessions.

#### Scenario: Console renders sessions
- **WHEN** the console is expanded after actions have run
- **THEN** the user can see recent session titles and statuses without triggering shell execution
