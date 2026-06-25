import Foundation
import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

let actionCoordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 100))
expect(actionCoordinator.preferences.accent == .mint, "Preferences should default from C++ core")
expect(actionCoordinator.preferences.expandedWidth == 760, "Comfortable panel width should come from C++ core")
actionCoordinator.setDensity(.compact)
expect(actionCoordinator.preferences.density == .compact, "Density should update through C++ core")
expect(actionCoordinator.preferences.expandedWidth == 700, "Compact panel width should come from C++ core")
actionCoordinator.setAccent(.amber)
expect(actionCoordinator.theme.accent == .amber, "Accent should update theme through C++ core")
expect(actionCoordinator.projectProfile.name == "Junimo", "Project profile should come from C++ core")
expect(actionCoordinator.projectProfile.stack.contains("C++23"), "Project profile should describe C++23 stack")
expect(actionCoordinator.commandResults.count >= 6, "Default command palette should include C++ commands")
actionCoordinator.updateCommandQuery("focus")
expect(actionCoordinator.commandResults.contains(where: { $0.id == "pomodoro-25" }), "Command search should return focus commands")
actionCoordinator.performCommand(id: "pomodoro-10s", now: Date(timeIntervalSince1970: 101))
expect(actionCoordinator.activePomodoro != nil, "Command launch should start Pomodoro")
expect(actionCoordinator.sessions.first?.title == "Pomodoro focus", "Pomodoro command should create session")
actionCoordinator.cancelPomodoro(now: Date(timeIntervalSince1970: 102))

actionCoordinator.performAction(id: "codex")
expect(actionCoordinator.agents.first(where: { $0.id == "codex" })?.status == .running, "Codex agent should be running")
expect(actionCoordinator.recentActivities.first?.title == "Started Codex", "Action should record activity")
expect(actionCoordinator.recentActivities.first?.detail == "C++ core marked Codex as running", "Action should be backed by C++ core")
expect(actionCoordinator.sessions.first?.status == .running, "Agent action should create running session")

let hoverStart = Date(timeIntervalSince1970: 200)
let hoverCoordinator = TaskCoordinator(now: hoverStart)
hoverCoordinator.pointerEntered()
hoverCoordinator.pointerExited(at: hoverStart)
hoverCoordinator.advanceTime(to: hoverStart.addingTimeInterval(0.5))
expect(hoverCoordinator.isExpanded, "Console should stay expanded before collapse delay")
hoverCoordinator.advanceTime(to: hoverStart.addingTimeInterval(1.4))
expect(!hoverCoordinator.isExpanded, "Console should collapse after delay")

let pomodoroStart = Date(timeIntervalSince1970: 300)
let pomodoroCoordinator = TaskCoordinator(now: pomodoroStart)
pomodoroCoordinator.startPomodoro(duration: 60, now: pomodoroStart)
expect(pomodoroCoordinator.activePomodoro != nil, "Pomodoro should start")
expect(pomodoroCoordinator.sessions.first?.title == "Pomodoro focus", "Pomodoro should create session")
pomodoroCoordinator.cancelPomodoro(now: pomodoroStart.addingTimeInterval(10))
expect(pomodoroCoordinator.activePomodoro == nil, "Pomodoro should cancel")
expect(pomodoroCoordinator.recentActivities.first?.title == "Pomodoro cancelled", "Cancel should record activity")
expect(pomodoroCoordinator.recentActivities.first?.detail == "Focus session stopped in C++ core", "Cancel should be backed by C++ core")
pomodoroCoordinator.startPomodoro(duration: 60, now: pomodoroStart)
pomodoroCoordinator.advanceTime(to: pomodoroStart.addingTimeInterval(60))
expect(pomodoroCoordinator.activePomodoro == nil, "Pomodoro should complete")
expect(pomodoroCoordinator.pendingNotifications.first?.title == "Pomodoro complete", "Completion should request notification")
expect(pomodoroCoordinator.recentActivities.first?.title == "Pomodoro complete", "Completion should record activity")
expect(pomodoroCoordinator.recentActivities.first?.detail == "Reminder request created in C++ core", "Completion should be backed by C++ core")

print("JunimoCore smoke tests passed")
