# console-feature Specification

## Purpose
Define the Swift console feature boundary for action/catalog projections, command search, project profile, recent activity, sessions, and running-agent start effects while keeping portable action/session policy in core.

## Requirements
### Requirement: Console Feature Owns Action And Command Projection

The Swift layer SHALL route console action state, command search, project profile, recent activity, sessions, and action start effects through a console feature owner.

#### Scenario: Feature exposes command and project projections

- **WHEN** console feature initializes from core
- **THEN** it SHALL expose project profile and default command results
- **WHEN** command query changes
- **THEN** it SHALL expose matching command results

#### Scenario: Feature emits agent start effect

- **WHEN** a known agent action is performed through the feature
- **THEN** the feature SHALL refresh agents, recent activities, and sessions from core
- **AND** it SHALL emit an agent start effect for running agent results

#### Scenario: Coordinator remains compatibility facade

- **WHEN** existing UI code calls `TaskCoordinator.performAction`
- **THEN** the coordinator SHALL delegate action execution to the console feature
- **AND** Codex monitor state SHALL remain adapter-owned rather than being created from console action placeholders
