# notch-anchor-and-quit Specification

## Purpose
Define top-system-boundary panel anchoring and stable quit affordances through the expanded panel and menu bar.
## Requirements
### Requirement: Full-screen top-center anchoring
The system SHALL request anchoring the floating panel near the physical top-center screen area and accept macOS clamping to the top system-allowed boundary.

#### Scenario: App launches
- **WHEN** Junimo launches
- **THEN** the collapsed capsule frame is computed from the full screen frame rather than the visible frame, with launch health recording any system top-boundary clamp

### Requirement: Stable panel quit
The expanded console SHALL expose a visible quit control.

#### Scenario: User clicks quit
- **WHEN** the user clicks the quit control in the expanded console
- **THEN** Junimo terminates through `NSApplication`

### Requirement: Menu bar quit
The app SHALL expose a menu bar status item with a Quit command.

#### Scenario: User opens status menu
- **WHEN** the user opens the Junimo status item menu
- **THEN** the menu includes Show and Quit commands
