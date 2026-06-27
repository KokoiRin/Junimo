# preferences-feature Specification

## ADDED Requirements

### Requirement: Preferences Feature Owns UI Preference Projection

The Swift layer SHALL route UI preference and theme projection through a preferences feature owner while keeping preference policy in core.

#### Scenario: Feature exposes core preference snapshot

- **WHEN** preferences feature initializes from core
- **THEN** it SHALL expose accent, density, expanded panel size, and top offset preferences
- **AND** theme accent SHALL match the preference accent

#### Scenario: Feature updates accent and density

- **WHEN** accent is changed through the feature
- **THEN** the feature SHALL update preferences and theme from the core result
- **WHEN** density is changed through the feature
- **THEN** the feature SHALL expose the core-returned density and expanded panel size

#### Scenario: Coordinator remains compatibility facade

- **WHEN** existing UI code calls `TaskCoordinator.setAccent` or `TaskCoordinator.setDensity`
- **THEN** the coordinator SHALL delegate preference updates to the feature
- **AND** the existing layout preferences callback SHALL still receive the updated preferences
