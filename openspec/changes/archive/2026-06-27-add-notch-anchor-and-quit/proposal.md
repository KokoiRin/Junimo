## Why

The capsule currently uses the visible screen frame, which places it below the menu bar instead of near the physical top-center notch area. Users also need a stable, discoverable quit path.

## What Changes

- Anchor the floating capsule against the full screen frame instead of `visibleFrame`.
- Add a menu bar status item with Show and Quit commands.
- Add a visible quit button in the expanded console header.
- Include launch health data that proves the panel is near the top of the full screen.

## Capabilities

### New Capabilities
- `notch-anchor-and-quit`: Top-center full-screen anchoring plus stable quit controls.

### Modified Capabilities

## Impact

- Updates AppKit panel positioning.
- Adds a local macOS status item.
- Updates SwiftUI header controls and tests/scripts as needed.
