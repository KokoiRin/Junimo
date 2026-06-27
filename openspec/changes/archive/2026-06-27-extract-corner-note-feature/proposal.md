# Extract Corner Note Feature

## Why

Corner Note is now a real product surface: it has a separate edge trigger, expansion lifecycle, editable note text, and todo list. The persisted note/todo domain already lives behind `CornerNoteCore`, but Swift-facing state is still projected directly through `TaskCoordinator`.

As more note behavior is added, such as quick capture, recovery, persistence diagnostics, or sync, the app needs a clear feature owner instead of adding more note-specific rules to the coordinator.

## What Changes

- Add a `CornerNoteFeature` that owns the Swift-facing expanded/text/todos projection.
- Keep `CornerNoteCore` as the persistence/domain backend for note and todo mutations.
- Keep `TaskCoordinator` as a compatibility facade for existing SwiftUI views.
- Add direct tests proving Corner Note edits flow through the feature boundary.

## Non-Goals

- Do not redesign the Corner Note UI.
- Do not change persistence format or cache location.
- Do not add sync, recovery, or cross-device behavior in this change.
