## Why

Desktop visual validation can be blocked by macOS lock-screen or black-screen security states. Junimo needs an internal launch health snapshot so automated checks can prove that the app process initialized its AppKit panel and C++ core-backed state even when screenshots cannot see the UI.

## What Changes

- Add an app-side launch health reporter that writes a local JSON snapshot after the panel is shown.
- Include process id, bundle/executable path, panel frame, collapsed/expanded state, panel level, and C++ core-backed state counts/preferences.
- Add a script that launches the app bundle and validates the health snapshot.
- Add health validation to the full verification script.

## Capabilities

### New Capabilities
- `launch-health-snapshot`: Local JSON health evidence for AppKit panel initialization and C++ core-backed state.

### Modified Capabilities

## Impact

- Adds Swift app-side diagnostics code.
- Adds verification scripts.
- Does not transmit data, mutate system settings, or execute external agent commands.
