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

print("JunimoCore shell DTO smoke tests passed")
