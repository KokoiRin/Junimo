## Why

Junimo needs to grow from a small fixed-action console into a useful local work surface. The next scale step is a command palette for quickly filtering actions and a project profile panel that gives context about the current workspace.

Both features should be backed by the C++23 core so the UI remains a native shell over portable domain behavior.

## What Changes

- Add C++23 domain models for command entries and workspace/project profile summaries.
- Add C++ core search over command title, subtitle, and tags.
- Expose command snapshots and project profile snapshots through the C ABI bridge.
- Add Swift bridge wrappers and coordinator state for command query, filtered commands, and active project profile.
- Update the expanded console UI with a compact command palette search field and a project profile section.
- Add tests covering C++ command search, Swift bridge-backed search state, and project profile visibility.

## Capabilities

### New Capabilities
- `command-palette`: Filter and launch command entries through a C++ core-backed palette.
- `project-profile`: Show a C++ core-backed workspace profile with project name, path, stack, and shortcuts.

### Modified Capabilities

## Impact

- Extends `Core/` C++ models and `TaskEngine`.
- Extends `c_api.h` and Swift bridge wrappers.
- Updates Swift coordinator and expanded console UI.
- Updates docs and verification scripts.
