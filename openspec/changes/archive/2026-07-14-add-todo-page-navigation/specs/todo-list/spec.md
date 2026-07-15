## ADDED Requirements

### Requirement: Go owns the authoritative Todo list
The Go backend SHALL own the ordered Todo collection, task validation, completion state, and persistence; Swift SHALL render backend snapshots and keep only unconfirmed editing drafts.

#### Scenario: Swift receives a Todo snapshot
- **WHEN** the backend returns a state snapshot containing Todo items
- **THEN** Swift renders those items without maintaining a second authoritative list

### Requirement: User can create a Todo
The system SHALL create an open Todo with a stable unique identifier when the normalized title is between 1 and 120 characters, and SHALL insert the new item at the beginning of the ordered list.

#### Scenario: Create a valid Todo
- **WHEN** the user confirms a title containing non-whitespace characters
- **THEN** the backend trims surrounding whitespace, persists an open Todo, and returns it at the beginning of the list

#### Scenario: Reject an empty Todo
- **WHEN** the user confirms an empty or whitespace-only title
- **THEN** the backend rejects the intent and leaves the list unchanged

#### Scenario: Reject an overlong Todo
- **WHEN** the normalized title contains more than 120 characters
- **THEN** the backend rejects the intent and leaves the list unchanged

### Requirement: User can rename a Todo
The system SHALL replace the title of an existing Todo only after the new title passes the same normalization and length rules as creation.

#### Scenario: Rename an existing Todo
- **WHEN** the user confirms a valid new title for an existing Todo
- **THEN** the backend persists the new title while preserving the task identifier, state, and relative order

#### Scenario: Rename an unknown Todo
- **WHEN** the user attempts to rename an identifier that is not present
- **THEN** the backend rejects the intent and leaves the list unchanged

### Requirement: User can set Todo completion explicitly
The system SHALL accept an explicit desired completion value and SHALL map it to open or completed without toggle semantics.

#### Scenario: Complete an open Todo
- **WHEN** the user requests completed=true for an open Todo
- **THEN** the backend persists the Todo as completed

#### Scenario: Repeat the same completion request
- **WHEN** the same completion value is applied more than once
- **THEN** the Todo remains in that state and does not flip back

#### Scenario: Restore a completed Todo
- **WHEN** the user requests completed=false for a completed Todo
- **THEN** the backend persists the Todo as open

### Requirement: User can delete a Todo
The system SHALL remove an existing Todo from the authoritative list and persistence when the user confirms deletion.

#### Scenario: Delete an existing Todo
- **WHEN** the user deletes a Todo that exists
- **THEN** the backend removes it and returns a snapshot without that item

#### Scenario: Delete an unknown Todo
- **WHEN** the user deletes an identifier that is already absent
- **THEN** the operation is idempotent and the current list remains unchanged

### Requirement: Todo changes are durable and atomic
The backend SHALL restore persisted Todos on restart and SHALL not publish a candidate mutation unless its atomic file save succeeds.

#### Scenario: Restart after successful mutations
- **WHEN** the backend restarts after Todo changes were saved
- **THEN** it restores the same identifiers, titles, states, and order

#### Scenario: Persistence fails
- **WHEN** the Todo store fails while saving a candidate mutation
- **THEN** the backend returns an error and subsequent snapshots retain the previously persisted list

#### Scenario: Todo storage cannot be loaded
- **WHEN** the Todo file is unreadable or malformed during startup
- **THEN** the Todo snapshot is unavailable while Pomodoro, Codex, health, and state endpoints remain usable

### Requirement: Todo and Pomodoro remain independent
Todo intents SHALL NOT change Pomodoro state, and Pomodoro intents or completion SHALL NOT create, complete, rename, or delete Todos.

#### Scenario: Mutate Todo during a running Pomodoro
- **WHEN** the user creates, renames, completes, or deletes a Todo while a Pomodoro is running
- **THEN** the Pomodoro mode, status, duration, and remaining-time semantics remain unchanged

#### Scenario: Pomodoro completes with open Todos
- **WHEN** a Pomodoro completes while open Todos exist
- **THEN** every Todo retains its existing title, completion state, identifier, and order
