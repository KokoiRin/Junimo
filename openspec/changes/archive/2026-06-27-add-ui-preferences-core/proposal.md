## Why

Junimo has visible theme controls, but preferences are still Swift-only transient state. Moving UI preference ownership into the C++23 core makes the core the single source for user-facing console configuration and prepares for future persistence.

## What Changes

- Add C++23 UI preference model for accent, density, expanded panel size, and top offset.
- Expose preference snapshots and update operations through the C ABI bridge.
- Add Swift preference models and coordinator methods that read/write preferences through the C++ bridge.
- Extend the expanded console with density controls next to existing accent controls.
- Use preferences to drive expanded panel sizing.
- Add tests for C++ and Swift preference updates.

## Capabilities

### New Capabilities
- `ui-preferences`: C++ core-backed console preferences for theme and layout density.

### Modified Capabilities

## Impact

- Extends C++ models, `TaskEngine`, and C API.
- Extends Swift bridge/coordinator and panel sizing.
- Does not add disk persistence, login items, or system settings changes.
