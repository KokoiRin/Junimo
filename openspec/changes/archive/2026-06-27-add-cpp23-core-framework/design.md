## Context

The repository currently builds a Swift/AppKit hover console through direct `swiftc` scripts. SwiftPM is present but blocked by the local CommandLineTools `PackageDescription` linking issue. The visible desktop could not be tested because the Mac was locked during screenshot verification, though the foreground process stayed alive.

The user wants the tool to grow beyond a tiny UI and expects the core to use the latest practical C++ standard, C++23.

## Goals / Non-Goals

**Goals:**
- Keep Swift/AppKit responsible for native macOS windows and SwiftUI rendering.
- Introduce `Core/` as a portable C++23 domain layer with zero UI dependencies.
- Provide direct `clang++` scripts for building and testing the C++ core.
- Provide an `.app` bundle script so Junimo can be launched by `open`.
- Document feature expansion direction and the Swift-to-C++ bridge path.

**Non-Goals:**
- Do not rewrite the existing Swift coordinator into C++ in this step.
- Do not introduce CMake unless the environment has it or the project needs multi-platform build generation.
- Do not bind real Codex/Hermes/terminal execution protocols yet.
- Do not add persistence, login items, signing, or distribution packaging yet.

## Decisions

1. **C++23 core starts as a static library plus tests**
   - `Core/include/junimo/core/*.hpp` exposes portable interfaces.
   - `Core/src/*.cpp` implements domain behavior.
   - `Core/tests/*.cpp` provides dependency-free smoke tests.
   - Direct `clang++ -std=c++23` scripts keep the framework verifiable on this machine.

2. **Swift remains the UI shell for now**
   - Swift/AppKit is the correct layer for `NSPanel`, hover, non-activating behavior, and system notifications.
   - C++ will first own portable concepts: task catalog, agent state transitions, activity feed rules, Pomodoro state, and later planning/execution policy.

3. **Bridge later through C ABI or Swift C++ interop**
   - The immediate framework should not depend on Swift.
   - The next implementation step can add a narrow bridge such as `CoreBridge` with C-compatible handles if Swift C++ interop is awkward under the current CLT setup.

4. **`.app` bundle is build output, not a full release package**
   - The bundle script creates `Junimo.app` with `Info.plist`, `MacOS/Junimo`, and copied dynamic library.
   - Signing, notarization, login items, and installer packaging remain future work.

## Risks / Trade-offs

- **C++ core duplicates some Swift domain concepts temporarily** -> Keep the C++ API small and document Swift-to-C++ migration as the next slice.
- **No CMake installed** -> Use direct scripts now; add CMake later when dependency/tooling policy is clear.
- **Visual verification blocked by lock screen** -> Use process and launch smoke tests now; rerun UI hover/click checks after the desktop is unlocked.
- **SwiftPM still blocked locally** -> Continue documenting direct scripts as authoritative until Xcode/CLT is repaired.
