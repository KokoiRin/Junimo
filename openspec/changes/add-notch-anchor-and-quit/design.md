## Context

`NSScreen.visibleFrame` excludes the menu bar and Dock. Using it makes the panel sit below the menu bar. A free-floating `NSPanel` can be placed closer to the physical top edge with `NSScreen.frame`, but it still cannot become a first-class menu bar item. A separate `NSStatusItem` is the appropriate native menu bar affordance.

## Goals / Non-Goals

**Goals:**
- Move panel anchoring to full-screen top-center coordinates.
- Provide stable quit from both expanded panel and menu bar status item.
- Keep non-activating panel behavior.

**Non-Goals:**
- Do not inject content into the actual camera notch or system-reserved menu bar area.
- Do not add login items or system setting changes.

## Decisions

1. **Use `screen.frame` for the floating panel**
   - This requests placement near the physical top edge.
   - macOS may clamp normal app windows and panels below the menu bar/notch-reserved region.
   - The status bar level keeps it visible above normal app windows within the system-allowed area.

2. **Use `NSStatusItem` for menu bar integration**
   - Menu bar placement is system-controlled.
   - The status item provides reliable Show/Quit controls.

## Risks / Trade-offs

- **Floating panel may be clamped below the menu bar on some displays** -> Use `NSStatusItem` for true menu bar presence and document this as a macOS system boundary.
- **True notch occupation is not public API** -> Use status item for menu bar-native presence.
