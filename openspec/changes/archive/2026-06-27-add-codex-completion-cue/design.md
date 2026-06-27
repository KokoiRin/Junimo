## Context

Junimo already creates `CodexReviewItem` state when a known Codex thread moves from running or waiting into completed or failed. The expanded island can show the latest result, and the collapsed island has an attention glow/count. After replacing the idle moon icon with quota text, the collapsed right-side area is now a meaningful status slot; pending Codex results should take priority there because completion is more urgent than passive quota.

## Goals / Non-Goals

**Goals:**
- Make pending Codex completion/failure obvious in the collapsed island.
- Keep the cue actionable by preserving the existing expanded acknowledgement flow.
- Keep the cue state derived from `CodexReviewItem`, not a separate UI-only flag.
- Keep quota visible when there are no pending review items.

**Non-Goals:**
- Do not start real Codex tasks from Junimo.
- Do not add notification history or persistence.
- Do not add pixel-level UI automation in this slice.

## Decisions

1. **Review item owns short cue text**
   - Add a public computed cue on `CodexReviewItem`.
   - Completed results display as `Codex done`; failed results display as `Codex failed`.
   - This gives tests a public behavior surface and keeps SwiftUI formatting thin.

2. **Collapsed right slot prioritizes pending results**
   - If `codexReviewItems.first` exists, the collapsed right pill shows the review cue instead of quota.
   - If no review is pending, it shows `codexMonitor.usage.summaryText` as it does now.
   - Failed results use the existing red attention color; completed results use the accent color.

3. **Expanded acknowledgement remains the action**
   - The expanded island already shows latest review detail and a compact acknowledgement button.
   - This change strengthens the collapsed entry point without creating a second acknowledgement path.

## Risks / Trade-offs

- **Long thread titles cannot fit in the collapsed slot** -> Keep the collapsed cue generic and show details only after expand.
- **No pixel assertion yet** -> Protect cue text and review state with direct smoke tests, then rely on app build/functional scenario for UI compilation and launch.
