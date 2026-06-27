## Why

Junimo can observe Codex completion and failure events, but the visible alert currently depends on transient notification delivery state. Since Codex is still the primary work surface, Junimo should first become a reliable attention layer that keeps completed or failed Codex work visible until the user handles it.

## What Changes

- Add Codex review items that are created when a known active Codex thread becomes completed or failed.
- Keep review items independent from system notification delivery.
- Show a persistent collapsed-island attention signal while Codex review items are pending.
- Surface the latest pending Codex result in the expanded island and provide a clear acknowledgement action.

## Capabilities

### New Capabilities
- `codex-review-attention`: Persistent attention state for Codex results that need review.

### Modified Capabilities
- `codex-monitor`: Terminal thread transitions now create both transient notification requests and persistent review items.

## Impact

- Extends JunimoCore state models and `TaskCoordinator`.
- Updates the SwiftUI island to reflect pending Codex reviews.
- Adds direct smoke coverage for review item creation and acknowledgement.
