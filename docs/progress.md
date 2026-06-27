# Progress

## 2026-06-27

### Follow-up: Codex Thread Lifecycle

Completed:

- Added a normalized Codex lifecycle layer with `running`, `waiting`, `open`, `completed`, and `failed` states.
- Preserved app-server `notLoaded`, `idle`, and unknown non-terminal statuses as open work instead of quota-only idle.
- Removed snapshot-absence completion: a missing active thread no longer creates a completion notification or review item.
- Added active/open/terminal lifecycle counts to health snapshots and health-script assertions.
- Updated collapsed status priority so open work shows as `Codex open N` before quota text.

Verified:

```bash
scripts/test.sh
scripts/verify.sh
```

Note: `swift test` is still not a valid project harness because the existing SwiftPM target lacks the required macOS availability configuration for Combine/AppKit APIs.

## 2026-06-27

### Follow-up: Codex Monitor Diagnostics

Completed:

- Added collapsed Codex status priority for active work: pending review first, then `Codex running` / `Codex waiting`, then quota.
- Added direct acknowledgement from the collapsed Codex status pill and review-count badge, so completed results can be cleared without expanding the island.
- Removed the obsolete three-second completion-preview prompt from the dock.
- Added Codex monitor fields to launch health snapshots: usage, thread counts, latest thread, review counts, collapsed status, and refresh time.
- Rewrote the health snapshot after Codex monitor refreshes or realtime events so diagnostics can show post-launch monitor state.
- Added health-script assertions that Codex diagnostic fields are present.

Verified:

```bash
scripts/test.sh
scripts/build_app.sh
```

## 2026-06-27

### Follow-up: Codex Completion Cue

Completed:

- Added OpenSpec change `add-codex-completion-cue`.
- Added `CodexReviewItem.cueText` so completed and failed Codex results expose a short collapsed-island cue.
- Updated the collapsed right-side status pill to show the pending Codex result cue before quota text.
- Kept quota text as the default when no Codex review item is pending.

Verified:

```bash
scripts/test.sh
scripts/build_app.sh
openspec validate add-codex-completion-cue --strict
```

## 2026-06-27

### Follow-up: OpenSpec Archive And Testing Baseline

Completed:

- Archived all completed OpenSpec changes into `openspec/changes/archive/`.
- Synced long-lived requirements into `openspec/specs/`.
- Replaced stale active-change validation in `scripts/verify.sh` with strict OpenSpec validation:

```bash
openspec validate --all --strict
```

- Added `docs/testing.md` to describe the desired testing pyramid and harness roles.
- Added a mock-backed app bridge smoke test for `CodexMonitorRefreshBridge` fallback behavior.

Verified:

```bash
scripts/verify.sh
```

## 2026-06-27

### Follow-up: Codex Review Attention

Completed:

- Added OpenSpec change `add-codex-review-attention`.
- Added `CodexReviewItem` state in `TaskCoordinator`.
- Active-to-completed or active-to-failed Codex thread transitions now create a persistent review item in addition to the transient system notification request.
- Delivered system notifications no longer clear the review item.
- The collapsed island shows persistent attention when Codex results need review.
- The expanded island shows the latest pending Codex result and a compact acknowledgement control.

Verified:

```bash
scripts/verify.sh
```

## 2026-06-27

### Follow-up: Codex Realtime Adapter

Completed:

- Added OpenSpec change `add-codex-realtime-adapter`.
- Added realtime Codex event model and parser support for:
  - app-server `account/rateLimitsUpdated`
  - app-server `thread/statusChanged`
  - app-server terminal turn/thread events
  - `codex exec --json` `thread.started`, `turn.started`, `turn.completed`, `turn.failed`, and `error`
- Added `TaskCoordinator.applyCodexRealtimeEvent(...)` so usage/thread/finding events update the existing Codex monitor state.
- Added process-backed streams:
  - `ProcessCodexAppServerEventStream`
  - `ProcessCodexExecEventStream`
- Updated `CodexMonitorRefreshBridge` to start realtime app-server streaming while preserving periodic snapshot refresh as fallback.

Verified:

```bash
scripts/verify.sh
```

## 2026-06-25

### Follow-up: Launch Health Snapshot

Completed:

- Replaced the fragile implicit app entrypoint with an explicit AppKit `@main` runner:
  - `Sources/Junimo/JunimoMain.swift`
- Added local launch health diagnostics:
  - `Sources/Junimo/LaunchHealthReporter.swift`
  - `NotchPanelController.diagnostics()`
- Added health verification script:
  - `scripts/verify_launch_health.sh`
- Added functional launch scenario verification:
  - `scripts/verify_functional_scenario.sh`
- Added OpenSpec change `add-launch-health-snapshot`.

The app now writes `/tmp/junimo-health.json` after initialization. The snapshot includes:

- process id
- bundle and executable paths
- panel visibility, floating state, level, and frame
- C++ core-backed command count, project name, preferences, activities, and sessions

Verified:

```bash
scripts/verify_launch_health.sh
```

Result:

```text
Junimo launch health verified
```

Example health evidence:

```json
{
  "status": "ok",
  "panel": {
    "visible": true,
    "floating": true,
    "frame": {
      "width": 236,
      "height": 46
    }
  },
  "console": {
    "agents": 2,
    "commands": 6,
    "activities": 1,
    "project": "Junimo",
    "preferences": {
      "accent": "mint",
      "density": "comfortable"
    }
  }
}
```

This does not replace unlocked-screen hover/click QA, but it proves the `.app` initialized the AppKit panel and C++ core-backed state even when screenshots are blocked by the secure desktop.

Functional scenario evidence:

```bash
scripts/verify_functional_scenario.sh
```

Result:

```text
Junimo functional scenario verified
```

The scenario runs inside the app process and exercises:

- hover expansion through `TaskCoordinator.pointerEntered`
- command search with query `focus`
- command execution for Codex and Pomodoro
- session creation
- activity recording
- density update to compact
- panel resize to `700x470`

### Follow-up: Notch Anchor And Quit

Completed:

- Changed floating panel positioning to request full-screen top-center coordinates.
- Added a menu bar `NSStatusItem` with Show and Quit.
- Added an expanded-console quit button.
- Added health checks for top system-boundary anchoring.
- Added OpenSpec change `add-notch-anchor-and-quit`.

Observed technical boundary:

- macOS clamps the free-floating `NSPanel` below the menu bar/notch reserved region on this machine.
- Health evidence after the change shows `distanceFromTop` around `33`, matching the menu bar area, even though the app requests full screen top anchoring.
- True menu bar presence is handled through `NSStatusItem`; exact center/notch occupation is not reliable through public panel APIs.

### Follow-up: C++ UI Preferences

Completed:

- Added C++23 UI preference model:
  - accent
  - density
  - expanded panel width/height
  - top offset
- Extended C ABI bridge with scalar preference getters and setters.
- Added Swift `ConsoleDensity` and `ConsolePreferences`.
- `TaskCoordinator` now initializes theme/layout preferences from C++ core.
- Accent buttons now write through C++ preferences.
- Added density controls:
  - Comfort
  - Compact
- Expanded panel sizing now reads `coordinator.preferences`.
- Added OpenSpec change `add-ui-preferences-core`.

Verified:

```bash
scripts/test.sh
scripts/test_cpp.sh
scripts/build.sh
scripts/build_app.sh
openspec validate add-ui-preferences-core --strict
```

Swift smoke tests now verify C++-backed default preferences, compact layout sizing, and accent updates.

### Follow-up: Session Timeline

Completed:

- Added C++23 execution session model:
  - `SessionStatus`
  - `ExecutionSession`
- C++ core now records sessions for:
  - agent actions as running sessions
  - project/tool actions as succeeded sessions
  - Pomodoro start as a running focus session
- Extended C ABI bridge with `junimo_core_recent_sessions`.
- Added Swift `ExecutionSessionSummary` and coordinator `sessions` state.
- Added expanded-console `Sessions` section.
- Added OpenSpec change `add-session-timeline`.

Verified:

```bash
scripts/test.sh
scripts/test_cpp.sh
scripts/build.sh
scripts/build_app.sh
openspec validate add-session-timeline --strict
```

Swift smoke tests now verify that C++ session snapshots appear after command/action/Pomodoro flows.

### Follow-up: Command Palette And Project Profile

Completed:

- Added C++23 command/profile models:
  - `CommandEntry`
  - `ProjectProfile`
- Added C++ command search and project profile snapshots in `TaskEngine`.
- Extended C ABI bridge with:
  - `junimo_core_search_commands`
  - `junimo_core_project_profile`
- Added Swift models and coordinator state:
  - `CommandPaletteEntry`
  - `ProjectProfileSummary`
  - `commandQuery`
  - `commandResults`
  - `projectProfile`
- Expanded SwiftUI console with:
  - command palette search field
  - C++ backed command results
  - project profile section
  - command result launching through `TaskCoordinator.performCommand(id:)`
- Added OpenSpec change `add-command-palette-profiles`.

Verified:

```bash
scripts/test.sh
scripts/test_cpp.sh
scripts/build.sh
scripts/build_app.sh
openspec validate add-command-palette-profiles --strict
```

The Swift smoke test now verifies:

- project profile name and C++23 stack
- default command palette result count
- `focus` query returns Pomodoro command entries
- launching `pomodoro-10s` from command id starts a Pomodoro session

### Follow-up: Swift Calls C++ Core

Completed:

- Added C ABI bridge:
  - `Core/include/junimo/core/c_api.h`
  - `Core/src/c_api.cpp`
- Added Swift bridge wrapper:
  - `Sources/JunimoCore/CppCoreBridge.swift`
  - `Sources/JunimoCore/CoreBackends.swift`
- Updated `TaskCoordinator` so action execution and Pomodoro lifecycle go through `CppBackedCore` by default.
- Updated direct Swift and `.app` scripts to build/link `libjunimo_core_bridge.dylib`.
- Added OpenSpec change `bridge-swift-to-cpp-core`.
- Relaunched the C++-bridged `.app` successfully:

```text
47811 /Users/guoysh/Documents/Junimo/.build/app/Junimo.app/Contents/MacOS/Junimo
```

Verified:

```bash
scripts/test.sh
```

The Swift smoke test now asserts C++ core result strings:

```text
C++ core marked Codex as running
Focus session stopped in C++ core
Reminder request created in C++ core
```

```bash
scripts/test_cpp.sh
scripts/build.sh
scripts/build_app.sh
openspec validate bridge-swift-to-cpp-core --strict
```

All passed.

### Follow-up: App Bundle And C++23 Core

Completed:

- Added `.app` bundle build and launch scripts:
  - `scripts/build_app.sh`
  - `scripts/launch_app.sh`
- Launched the app bundle successfully through macOS:

```text
42204 /Users/guoysh/Documents/Junimo/.build/app/Junimo.app/Contents/MacOS/Junimo
```

- Added C++23 core framework under `Core/`:
  - `Core/include/junimo/core/models.hpp`
  - `Core/include/junimo/core/task_engine.hpp`
  - `Core/src/models.cpp`
  - `Core/src/task_engine.cpp`
  - `Core/tests/core_smoke_test.cpp`
- Added C++ scripts:
  - `scripts/build_cpp.sh`
  - `scripts/test_cpp.sh`
- Added `docs/architecture.md` with the Swift/AppKit shell, C++23 core boundary, bridge plan, and next feature modules.
- Added OpenSpec change `add-cpp23-core-framework`.

Verified:

```bash
scripts/test_cpp.sh
```

Result:

```text
Junimo C++23 core smoke tests passed
```

```bash
scripts/build_app.sh
```

Result:

```text
/Users/guoysh/Documents/Junimo/.build/app/Junimo.app
```

```bash
scripts/launch_app.sh
```

Result:

```text
42204 /Users/guoysh/Documents/Junimo/.build/app/Junimo.app/Contents/MacOS/Junimo
```

```bash
openspec validate add-cpp23-core-framework --strict
```

Result:

```text
Change 'add-cpp23-core-framework' is valid
```

Visual verification status:

- A screenshot check showed the macOS lock screen, so direct hover/click visual testing is blocked until the user session is unlocked.
- Process-level app launch is verified.
- Core behavior is verified through Swift and C++ smoke tests.

### Completed

- Initialized OpenSpec with change `bootstrap-hover-console`.
- Added specs for `hover-console` and `pomodoro-timer`.
- Created SwiftPM project structure:
  - `JunimoCore` for coordinator, models, adapter contracts, mock adapter, activity, theme, and Pomodoro state.
  - `Junimo` executable for AppKit panel, SwiftUI surface, and notification delivery adapter.
  - `JunimoTests` for SwiftPM/XCTest coverage when SwiftPM is usable.
- Added direct compiler scripts for the current local CLT environment:
  - `scripts/test.sh`
  - `scripts/build.sh`
- Implemented the first complete chain:
  - collapsed capsule
  - hover expand
  - show mock agents, actions, theme, recent activity, and Pomodoro controls
  - click action through `TaskCoordinator` and `TaskExecutionAdapter`
  - update agent status and recent activity
  - delayed collapse after pointer exit
- Implemented basic Pomodoro:
  - start a default 25 minute session
  - start a short 10 second development session
  - cancel active session
  - complete elapsed session
  - create a notification request and deliver it through `UserNotificationReminderAdapter`

### Verification

Passed:

```bash
scripts/test.sh
```

Result:

```text
JunimoCore smoke tests passed
```

Passed:

```bash
scripts/build.sh
```

Result:

```text
/Users/guoysh/Documents/Junimo/.build/direct/Junimo
```

Passed:

```bash
openspec validate bootstrap-hover-console --strict
```

Result:

```text
Change 'bootstrap-hover-console' is valid
```

Attempted but blocked by local toolchain:

```bash
swift build
swift test
```

Failure:

```text
Invalid manifest
Undefined symbols for architecture arm64:
PackageDescription.Package.__allocating_init(...)
```

Environment note:

```bash
xcode-select -p
# /Library/Developer/CommandLineTools

xcodebuild -version
# xcode-select: error: tool 'xcodebuild' requires Xcode
```

### Known Issues

- The current machine has CommandLineTools selected but no full Xcode available, and SwiftPM manifest linking is broken. Direct `swiftc` scripts are the verified build/test path for now.
- The direct build produces an executable, not a bundled `.app`; packaging, signing, login item behavior, and distribution are future work.
- System notification delivery requests authorization at completion time. A richer notification permission/settings flow is not implemented yet.
- UI verification is currently manual; core behavior is covered by direct smoke tests.
