## Context

`TaskCoordinator.updateCodexThread(...)` already detects active-to-terminal Codex thread transitions and creates a `NotificationRequest`. `ReminderDeliveryBridge` immediately marks delivered notifications as handled, so `pendingNotifications` is not a durable UI state. Junimo needs a separate review state that stays visible until the user acknowledges it.

## Goals / Non-Goals

**Goals:**
- Create a pending review item when a known active Codex thread becomes completed or failed.
- Keep pending review items after system notification delivery.
- Show an obvious collapsed island attention state.
- Let the user mark a Codex result reviewed from the expanded island.

**Non-Goals:**
- Do not start Codex tasks from Junimo.
- Do not add a full notification center.
- Do not sync review state across devices.
- Do not create a generic agent alert framework before another real agent needs it.

## Decisions

1. **Review state belongs in `TaskCoordinator`**
   - It is user-visible app state derived from Codex monitor events.
   - It should not live in C++ core because Codex protocol state remains Swift adapter-owned.

2. **Thread id is the review item identity**
   - A terminal update for the same thread refreshes the review item instead of duplicating it.
   - If a thread becomes active again, any stale review item for that thread is removed.

3. **System notification and review state are separate**
   - `pendingNotifications` remains a transient delivery queue.
   - `codexReviewItems` remains visible until acknowledged.

4. **First UI is compact**
   - The collapsed island shows a persistent attention glow and badge.
   - The expanded center stage and Alerts metric show the latest pending result.
   - A small icon button marks the latest review item handled.

## Risks / Trade-offs

- **No direct jump to Codex thread yet** -> Acceptable for this slice; Codex remains the primary app, and the main value is knowing something needs attention.
- **Review items are in-memory** -> Acceptable for the current local attention loop. Persistence can come later if missed results across app restarts become painful.
