## Why

Junimo has both a Swift coordinator and a C++23 core skeleton, but the app still runs its primary interaction behavior in Swift. To make "the core is C++" true in the running product, Swift must call a stable native bridge for action dispatch and Pomodoro lifecycle behavior.

## What Changes

- Add a narrow C ABI bridge over the C++23 `TaskEngine`.
- Add a Swift wrapper that owns the C++ engine handle and copies bridge results into Swift value models.
- Route `TaskCoordinator` action execution and Pomodoro lifecycle through the C++ bridge by default.
- Update build/test/app scripts to compile and link the C++ bridge library into both direct and `.app` builds.
- Add tests proving Swift-facing behavior is backed by the C++ bridge.

## Capabilities

### New Capabilities
- `swift-cpp-core-bridge`: Swift coordinator behavior is backed by the C++23 core through a stable C ABI bridge.

### Modified Capabilities

## Impact

- New C ABI header/source in `Core/`.
- New Swift wrapper in `Sources/JunimoCore`.
- Build/test scripts link Swift code against the C++ bridge dynamic library.
- No public UI behavior change is intended.
