## 1. Project Setup

- [x] 1.1 Create SwiftPM package with `JunimoCore` library, `Junimo` executable, and `JunimoTests`.
- [x] 1.2 Add README and progress documentation placeholders with build, test, and run commands.

## 2. Core Interaction Chain

- [x] 2.1 Define agent, action, activity, theme, and console expansion models in `JunimoCore`.
- [x] 2.2 Implement `TaskExecutionAdapter`, mock adapter, and `TaskCoordinator` so UI actions update status and activity through the adapter boundary.
- [x] 2.3 Add coordinator behavior for hover enter, delayed hover exit collapse, and cancelable collapse scheduling.

## 3. Pomodoro Timer

- [x] 3.1 Implement Pomodoro session state, creation, cancellation, completion, and notification request behavior.
- [x] 3.2 Add coordinator methods and activity entries for starting, cancelling, and completing Pomodoro sessions.

## 4. Native macOS UI

- [x] 4.1 Create AppKit application delegate and non-activating floating `NSPanel` positioned near the top-center screen area.
- [x] 4.2 Build SwiftUI collapsed capsule and expanded console views with mock agents, actions, recent activity, theme control, and Pomodoro controls.
- [x] 4.3 Wire hover events and button clicks to `TaskCoordinator` only.

## 5. Verification and Documentation

- [x] 5.1 Add unit tests for action execution, activity recording, hover collapse decisions, and Pomodoro lifecycle.
- [x] 5.2 Run `swift test`, `swift build`, and `openspec validate bootstrap-hover-console --strict`.
- [x] 5.3 Update README or `docs/progress.md` with progress, verification commands, and known issues.
