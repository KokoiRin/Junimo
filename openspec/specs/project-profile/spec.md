# project-profile Specification

## Purpose
Define the non-executing project profile snapshot shown in the expanded Junimo console.
## Requirements
### Requirement: Project profile snapshot
The system SHALL expose a project profile snapshot from the C++23 core.

#### Scenario: Console expands
- **WHEN** the expanded console renders
- **THEN** it can show a project name, path, technology stack, and shortcut labels supplied through the C++ bridge

### Requirement: Profile remains non-executing
The first project profile SHALL NOT execute shell commands or scan filesystems directly from the UI.

#### Scenario: Profile is displayed
- **WHEN** the UI shows project profile details
- **THEN** the values come from the core snapshot and do not trigger external system operations
