## Context

The app currently exposes accent color buttons in SwiftUI, and panel size is hard-coded in AppKit. The core already owns command/profile/session behavior. Preferences should follow the same pattern so later persistence or user profiles have a stable model.

## Goals / Non-Goals

**Goals:**
- Store current UI preferences in the C++23 core.
- Let Swift read preference snapshots and update accent/density through the bridge.
- Let AppKit panel sizing react to density preference.
- Keep controls lightweight and local.

**Non-Goals:**
- Do not persist preferences to disk yet.
- Do not add a separate settings window.
- Do not change macOS system settings.

## Decisions

1. **Density presets drive panel size**
   - Comfortable: 760x540.
   - Compact: 700x470.
   - Top offset remains available in the core snapshot for later notch positioning controls.

2. **Accent remains enum-like string values**
   - The C++ core stores `mint`, `amber`, or `graphite`.
   - Swift maps those values to `ConsoleAccent`.

3. **Panel controller observes coordinator layout changes**
   - `TaskCoordinator` publishes preferences.
   - `NotchPanelController` resizes when expansion or layout preferences change.

## Risks / Trade-offs

- **No persistence yet** -> Acceptable because this slice establishes ownership and bridge semantics first.
- **String enum mapping can drift** -> Tests cover known accent/density values.
