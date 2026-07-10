import Foundation
import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

let idleJSON = """
{
  "pomodoro": {
    "mode": "focus",
    "status": "idle",
    "durationSeconds": 1500,
    "remainingSeconds": 1500,
    "focusDurationSeconds": 1500,
    "breakDurationSeconds": 300
  }
}
"""

let state = try JSONDecoder().decode(SurfaceState.self, from: Data(idleJSON.utf8))
expect(state.pomodoro.mode == .focus, "Swift DTO should decode backend focus mode")
expect(state.pomodoro.status == .idle, "Swift DTO should decode backend idle status")
expect(state.pomodoro.remainingSeconds == 1500, "Swift DTO should decode backend remaining time")

let intent = BackendIntent(type: "pomodoro.startFocus", durationSeconds: 1500)
let encodedIntent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any]
expect(encodedIntent?["type"] as? String == "pomodoro.startFocus", "Swift intent should encode the backend action type")
expect(encodedIntent?["durationSeconds"] as? Int == 1500, "Swift intent should encode duration")

let codexJSON = """
{
  "pomodoro": {
    "mode": "focus",
    "status": "idle",
    "durationSeconds": 1500,
    "remainingSeconds": 1500,
    "focusDurationSeconds": 1500,
    "breakDurationSeconds": 300
  },
  "codex": {
    "status": "available",
    "primary": {"remainingPercent": 94, "windowDurationMinutes": 300, "resetsAt": 1783655023},
    "secondary": {"remainingPercent": 99, "windowDurationMinutes": 10080, "resetsAt": 1784241823}
  }
}
"""

let stateWithCodex = try JSONDecoder().decode(SurfaceState.self, from: Data(codexJSON.utf8))
expect(stateWithCodex.codex?.compactSummary == "5h 94%", "Collapsed quota should omit the Codex label and show the primary five-hour window")
expect(CodexUsageSnapshot(status: .loading).compactSummary == "…", "Loading quota should stay compact and not invent a number")
expect(CodexUsageSnapshot(status: .unavailable).compactSummary == "—", "Unavailable quota should degrade explicitly without widening the capsule")

expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 967) == 33,
    "Collapsed notch should fill the menu bar height"
)
expect(
    NotchPanelMetrics.collapsedHeight(screenTop: 1000, visibleTop: 1000) == 28,
    "Collapsed notch should keep its minimum height when the menu bar inset is hidden"
)

var completionGate = PomodoroCompletionNotificationGate()
let initialCompletion = completionGate.observe(
    PomodoroSnapshot(mode: .focus, status: .completed, remainingSeconds: 0)
)
expect(initialCompletion == nil, "Connecting to an already completed timer should not replay an old notification")

completionGate = PomodoroCompletionNotificationGate()
_ = completionGate.observe(PomodoroSnapshot(mode: .focus, status: .running, remainingSeconds: 1))
let focusCompletion = completionGate.observe(
    PomodoroSnapshot(mode: .focus, status: .completed, remainingSeconds: 0)
)
expect(focusCompletion == .focus, "A running focus timer becoming completed should request a focus notification")
let repeatedFocusCompletion = completionGate.observe(
    PomodoroSnapshot(mode: .focus, status: .completed, remainingSeconds: 0)
)
expect(repeatedFocusCompletion == nil, "Repeated completed snapshots should not duplicate a notification")

completionGate = PomodoroCompletionNotificationGate()
_ = completionGate.observe(PomodoroSnapshot(mode: .focus, status: .running, remainingSeconds: 1))
let unrelatedBreakCompletion = completionGate.observe(
    PomodoroSnapshot(mode: .rest, status: .completed, remainingSeconds: 0)
)
expect(unrelatedBreakCompletion == nil, "Changing modes must not fabricate a completion transition")

completionGate = PomodoroCompletionNotificationGate()
_ = completionGate.observe(PomodoroSnapshot(mode: .rest, status: .paused, remainingSeconds: 1))
let breakCompletion = completionGate.observe(
    PomodoroSnapshot(mode: .rest, status: .completed, remainingSeconds: 0)
)
expect(breakCompletion == .rest, "A paused break becoming completed should request a break notification")

print("JunimoCore shell DTO smoke tests passed")
