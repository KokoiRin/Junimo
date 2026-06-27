# runtime-composition Specification

## ADDED Requirements

### Requirement: Runtime Owns App Wiring Lifecycle

The app shell SHALL use a runtime composition object to own feature store, platform bridge, monitor, and diagnostic service lifecycle.

#### Scenario: App startup delegates product wiring to runtime

- **GIVEN** the macOS app is launching
- **WHEN** AppDelegate needs a coordinator for panels and needs to start background bridges
- **THEN** it SHALL get the coordinator from the runtime composition object
- **AND** it SHALL start Codex monitor and reminder delivery through the runtime
- **AND** AppDelegate SHALL NOT directly create Codex monitor or reminder delivery bridges

#### Scenario: Runtime preserves monitor and notification behavior

- **GIVEN** runtime composition starts with fake Codex provider, fake realtime stream, and fake reminder adapter
- **WHEN** the provider returns a monitor snapshot and the stream reports a degraded finding
- **THEN** the runtime coordinator SHALL expose that monitor snapshot and finding
- **WHEN** a Pomodoro completion creates a notification request
- **THEN** reminder delivery SHALL receive the request through the existing pending notification projection
- **AND** the pending queue SHALL be acknowledged after delivery

#### Scenario: Runtime teardown stops monitor stream

- **GIVEN** runtime composition has started Codex realtime monitoring
- **WHEN** the app terminates runtime
- **THEN** the realtime stream SHALL be stopped through the runtime lifecycle
