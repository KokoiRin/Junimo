## Why

Junimo already records Codex review items when a known Codex task completes or fails, but the collapsed island cue is still too subtle and easy to miss. This change turns Codex completion into a clear, glanceable, actionable product moment.

## What Changes

- Replace passive collapsed-state attention with a result cue that names the Codex terminal state.
- Keep quota visible when no review is pending, but prioritize completed/failed Codex results when review is needed.
- Make the expanded island show the latest result with an obvious acknowledge action.
- Keep review items independent from transient system notifications.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `codex-review-attention`: strengthen the visual and interaction requirements for completed or failed Codex results.

## Impact

- Affects `TaskCoordinator` review item state and SwiftUI collapsed/expanded island rendering.
- Adds direct smoke coverage for the review prompt state.
- Does not start real Codex tasks and does not change Codex realtime event parsing.
