# Extract Notification Outbox

## Why

Junimo now has multiple features that produce notification requests. Codex completion/failure creates notification effects through `CodexFeature`, and Pomodoro completion creates reminder requests through C++ core results. Both currently land directly in `TaskCoordinator.pendingNotifications`.

As more features add reminders or completion prompts, `TaskCoordinator` would become the shared notification queue owner. A small `NotificationOutbox` gives those features one place to enqueue pending requests while keeping platform delivery in the app shell.

## What Changes

- Add a `NotificationOutbox` state owner for pending `NotificationRequest` values.
- Keep `TaskCoordinator.pendingNotifications` as a compatibility projection for `ReminderDeliveryBridge`.
- Route Codex and Pomodoro notification requests through the outbox.
- Add direct tests for outbox queue semantics and coordinator compatibility behavior.

## Non-Goals

- Do not change UserNotifications permission or delivery behavior.
- Do not add scheduling, snooze, recurring reminders, or notification history.
- Do not move Pomodoro lifecycle out of C++ core.
