# hover-console Specification

## Purpose
Define Junimo's native collapsed capsule, hover expansion behavior, and first coordinator-mediated action surface.
## Requirements
### Requirement: Collapsed top-center capsule
The system SHALL show a small native macOS capsule near the top-center screen area when idle.

#### Scenario: App starts collapsed
- **WHEN** the user launches Junimo
- **THEN** the primary surface is a compact capsule positioned near the top-center screen area

### Requirement: Hover expands the console
The system SHALL expand the capsule into a lightweight console when the pointer hovers over the surface.

#### Scenario: Pointer enters capsule
- **WHEN** the pointer enters the capsule or expanded console surface
- **THEN** the console expands without requiring a click or keyboard focus

### Requirement: Delayed collapse after hover exit
The system SHALL delay collapsing the expanded console after the pointer leaves.

#### Scenario: Pointer leaves expanded console
- **WHEN** the pointer leaves the expanded console
- **THEN** the console remains expanded for a short delay before returning to capsule form

### Requirement: Console content
The expanded console SHALL show mock agent status, shortcut actions, project actions, recent activity, and theme controls.

#### Scenario: Expanded content is visible
- **WHEN** the console is expanded
- **THEN** the user can see mock agents, actions, recent activity, and at least one theme customization control

### Requirement: Adapter-mediated actions
The UI SHALL route action clicks through a task coordinator and task execution adapter.

#### Scenario: User clicks a shortcut action
- **WHEN** the user clicks an action in the expanded console
- **THEN** the task coordinator invokes an adapter, updates visible status, and records a recent activity entry

### Requirement: No direct shell execution from UI
The first version SHALL NOT execute shell commands or system operations directly from SwiftUI views.

#### Scenario: Action is triggered
- **WHEN** a SwiftUI view triggers an action
- **THEN** the view calls coordinator methods only and leaves execution details to adapters
