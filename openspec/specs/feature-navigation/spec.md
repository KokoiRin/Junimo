# feature-navigation Specification

## Purpose
TBD - created by archiving change add-todo-page-navigation. Update Purpose after archive.
## Requirements
### Requirement: Expanded panel provides independent feature navigation
The expanded Junimo panel SHALL present Focus and Todo as peer features in a left navigation rail and SHALL render exactly one selected feature page in the content area.

#### Scenario: Switch from Focus to Todo
- **WHEN** the user selects the Todo navigation item while the Focus page is visible
- **THEN** the Todo item becomes selected and the content area displays the Todo page

#### Scenario: Switch back to Focus
- **WHEN** the user selects the Focus navigation item while the Todo page is visible
- **THEN** the Focus item becomes selected and the content area displays the current Pomodoro state

### Requirement: Navigation remains a Swift shell concern
Feature selection SHALL be maintained by the Swift shell and SHALL NOT send a backend product intent or change Pomodoro, Todo, or Codex product state.

#### Scenario: Switch pages while a Pomodoro is running
- **WHEN** the user switches between Focus and Todo during a running Pomodoro
- **THEN** the Pomodoro continues running with unchanged product state

#### Scenario: Backend is unavailable during navigation
- **WHEN** the backend is unavailable and the user selects another feature page
- **THEN** the shell still switches the local page while each page displays the latest available backend state or its unavailable treatment

### Requirement: Navigation selection has a predictable lifecycle
The shell SHALL preserve the selected page across collapse and re-expansion during the same application run and SHALL start on the Focus page after application launch.

#### Scenario: Reopen the panel during one run
- **WHEN** the user selects Todo, lets the panel collapse, and expands it again
- **THEN** the Todo page remains selected

#### Scenario: Launch the application
- **WHEN** Junimo starts a new application run
- **THEN** the Focus page is selected by default

### Requirement: Todo editing prevents hover collapse
The shell SHALL keep the panel expanded while a Todo text editor owns an active editing session.

#### Scenario: Pointer leaves during editing
- **WHEN** the user is creating or renaming a Todo and moves the pointer outside the panel
- **THEN** the panel remains expanded until editing ends

#### Scenario: Editing ends outside the panel
- **WHEN** Todo editing ends while the pointer is already outside the panel
- **THEN** the panel collapses

### Requirement: Focus page keeps existing Pomodoro behavior without a Reminder card
The Focus page SHALL retain the existing duration, start, pause, resume, reset, break, repeat, and skip behaviors, and SHALL NOT introduce an in-app Reminder card or reminder queue.

#### Scenario: Pomodoro completes on any selected page
- **WHEN** a focus or break reaches completion while either feature page is selected
- **THEN** Go publishes the completion fact and Swift delivers the existing macOS completion notification once

### Requirement: Collapsed shell remains unchanged
The feature navigation change SHALL preserve the existing collapsed focus and Codex capsules.

#### Scenario: Panel collapses from either page
- **WHEN** the panel collapses from Focus or Todo
- **THEN** the shell displays the existing focus capsule and Codex usage capsule without Todo content
