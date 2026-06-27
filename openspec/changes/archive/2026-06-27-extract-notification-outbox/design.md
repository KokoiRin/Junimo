# Design: Extract Notification Outbox

## Target Type

[P1][架构预备]

## Core Behavior Semantics

当任意 feature 产生系统通知请求时，Swift core 应该先把请求放入 `NotificationOutbox`，app shell 再从 coordinator 的兼容投影中投递并确认；feature 不直接拥有通知队列，AppKit/UserNotifications 也不反向修改 feature state。

## Component Contract: `NotificationOutbox`

- Responsibility: own pending notification requests and remove delivered requests by ID.
- Not responsible for: deciding why a feature needs a notification, requesting OS permission, scheduling `UNNotificationRequest`, or storing history.
- Owner: Swift core notification boundary.
- Interface: `enqueue(_:)`, `enqueue(contentsOf:)`, `markDelivered(id:)`, and public `pending`.
- State: pending `NotificationRequest` values in enqueue order.
- Side effects: none.
- Invariants: marking an unknown ID is a no-op; marking a delivered ID removes that request only; queue order is preserved for pending requests.
- Lifecycle: constructed by runtime/coordinator and projected to app shell until a runtime container exists.
- Test surface: direct Swift tests over public queue methods plus coordinator compatibility tests.

## Migration

1. Add `NotificationOutbox` and direct test coverage.
2. Delegate `TaskCoordinator.pendingNotifications` mutations to the outbox.
3. Keep `ReminderDeliveryBridge` unchanged by preserving `$pendingNotifications`.
4. Update architecture docs and opportunities.

## Verification

- `scripts/test.sh`
- `scripts/build.sh`
- `openspec validate --all --strict`
- `git diff --check`
- `scripts/verify_ci.sh`
