# codex-status-attention Specification

## ADDED Requirements

### Requirement: Codex State Is Adapter-Owned

Junimo SHALL treat Codex running/waiting/open/completed/failed state as adapter-observed state, not as a placeholder created by the local Codex dock action.

#### Scenario: Codex action does not fake running state

- **WHEN** the user invokes the existing Codex action
- **THEN** Junimo SHALL record the console activity/session compatibility state
- **AND** Junimo SHALL NOT create a `junimo-local-codex` running thread
- **AND** collapsed Codex status SHALL remain based on adapter state or quota

### Requirement: Terminal Codex State Creates Attention

Junimo SHALL create persistent review attention when an observed Codex thread explicitly transitions from non-terminal work into completed or failed.

#### Scenario: Completed Codex thread shows done cue

- **GIVEN** a Codex thread is running
- **WHEN** the same thread is observed as completed
- **THEN** Junimo SHALL create one review item
- **AND** the collapsed status SHALL show `Codex done`
- **AND** the review item SHALL expose a completed attention cue suitable for animated UI presentation

#### Scenario: Failed Codex thread shows failed cue

- **GIVEN** a Codex thread is running
- **WHEN** the same thread is observed as failed
- **THEN** Junimo SHALL create one review item
- **AND** the collapsed status SHALL show `Codex failed`
- **AND** the review item SHALL expose a failed attention cue suitable for animated UI presentation

### Requirement: Attention Is Persistent And Clearable

Junimo SHALL keep Codex review attention until the user explicitly acknowledges it.

#### Scenario: Delivered notification does not clear review attention

- **GIVEN** a Codex terminal transition created a notification and review item
- **WHEN** the system notification is marked delivered
- **THEN** the review item SHALL remain visible

#### Scenario: Acknowledgement clears latest attention

- **GIVEN** a Codex review item is visible
- **WHEN** the user acknowledges the latest Codex review
- **THEN** the review item SHALL be removed
- **AND** collapsed status SHALL fall back to remaining open/running Codex state or quota

### Requirement: Collapsed Island Presents Animated Attention

The collapsed island SHALL render Codex review attention as an obvious visual cue with a persistent confirm action.

#### Scenario: Review attention renders a visible animated cue

- **GIVEN** at least one Codex review item exists
- **WHEN** the collapsed island is rendered
- **THEN** the right-side status pill SHALL use the review cue text
- **AND** the badge/pill SHALL be clickable to acknowledge the latest result
- **AND** the surrounding attention treatment SHALL include an animated phase rather than a static three-second prompt
