## 1. C ABI Bridge

- [x] 1.1 Add C header and C++ implementation for opaque C++ core engine handles.
- [x] 1.2 Add bridge functions for action dispatch, Pomodoro start/cancel/advance, and status snapshots.

## 2. Swift Integration

- [x] 2.1 Add Swift declarations/wrapper for bridge functions.
- [x] 2.2 Route `TaskCoordinator` action and Pomodoro behavior through the wrapper.
- [x] 2.3 Add Swift smoke assertions that prove bridge-backed behavior.

## 3. Build And Verification

- [x] 3.1 Add core bridge build script and update Swift direct/app scripts to link it.
- [x] 3.2 Run Swift tests, C++ tests, direct build, app bundle launch smoke, OpenSpec validation, and diff check.
- [x] 3.3 Update docs with the actual Swift-to-C++ bridge status.
