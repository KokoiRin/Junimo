# notification-outbox Specification

## ADDED Requirements

### Requirement: Notifications have a queue owner
The system SHALL route pending system notification requests through a Notification Outbox owner.

#### Scenario: Feature requests notification delivery
- **WHEN** a feature produces one or more `NotificationRequest` values
- **THEN** the requests are enqueued in the notification outbox
- **AND** `TaskCoordinator.pendingNotifications` exposes the outbox queue as a compatibility projection

### Requirement: Delivered notifications leave the queue
The system SHALL remove delivered notification requests by ID without mutating feature state.

#### Scenario: App shell marks notification delivered
- **WHEN** the app shell marks a notification ID delivered
- **THEN** the matching request is removed from the outbox
- **AND** unknown IDs leave the queue unchanged
