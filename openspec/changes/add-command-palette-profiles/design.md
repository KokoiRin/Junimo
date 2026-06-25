## Context

Junimo currently exposes a fixed set of actions in Swift UI, with action execution routed through the C++ bridge. This is enough for a tracer bullet but not enough for a larger tool. A command palette gives users a scalable action surface without expanding the UI too much.

The current repository has no persistence or real project detection. The first project profile should be a C++ core snapshot that can later be replaced by filesystem/workspace adapters.

## Goals / Non-Goals

**Goals:**
- Keep search/filtering logic in C++23.
- Keep UI state and rendering in SwiftUI.
- Use bounded C API snapshots to avoid memory ownership complexity.
- Add useful default commands and a default project profile for this repository.
- Preserve existing action execution behavior.

**Non-Goals:**
- Do not execute real shell commands.
- Do not scan the filesystem yet.
- Do not add persistence or user-editable profile files yet.
- Do not add keyboard global shortcuts yet.

## Decisions

1. **Command entries map to existing action IDs**
   - A command has id, title, subtitle, category, and tags.
   - Selecting a command calls `performAction(id:)` with the same id.
   - This keeps command launch behavior inside the existing adapter/core execution path.

2. **C API uses fixed-size snapshots**
   - The bridge returns up to 8 commands per query.
   - Each command field is copied into thread-local storage before Swift reads it.
   - This is enough for first UI and avoids cross-language ownership issues.

3. **Project profile is a core snapshot**
   - First profile contains `Junimo`, the current repository path, `Swift/AppKit + C++23`, and a few shortcut labels.
   - Later, a workspace adapter can hydrate the profile from real project files.

## Risks / Trade-offs

- **Thread-local snapshots are synchronous only** -> Acceptable for current UI; replace with owned buffers if async bridge calls appear.
- **Profile is currently static** -> Good enough for first scale-up; docs mark real workspace detection as future work.
- **Search is simple substring matching** -> It is predictable and testable; fuzzy ranking can come later.
