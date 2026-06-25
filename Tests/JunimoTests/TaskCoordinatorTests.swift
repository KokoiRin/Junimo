import XCTest
@testable import JunimoCore

final class TaskCoordinatorTests: XCTestCase {
    func testPreferencesComeFromCoreAndUpdateLayoutValues() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 80))

        XCTAssertEqual(coordinator.preferences.accent, .mint)
        XCTAssertEqual(coordinator.preferences.expandedWidth, 760)
        XCTAssertEqual(coordinator.preferences.expandedHeight, 220)

        coordinator.setDensity(.compact)

        XCTAssertEqual(coordinator.preferences.density, .compact)
        XCTAssertEqual(coordinator.preferences.expandedWidth, 700)

        coordinator.setAccent(.amber)

        XCTAssertEqual(coordinator.theme.accent, .amber)
        XCTAssertEqual(coordinator.preferences.accent, .amber)
    }

    func testCommandPaletteAndProjectProfileComeFromCore() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 90))

        XCTAssertEqual(coordinator.projectProfile.name, "Junimo")
        XCTAssertTrue(coordinator.projectProfile.stack.contains("C++23"))
        XCTAssertGreaterThanOrEqual(coordinator.commandResults.count, 6)

        coordinator.updateCommandQuery("focus")

        XCTAssertTrue(coordinator.commandResults.contains(where: { $0.id == "pomodoro-25" }))

        coordinator.performCommand(id: "pomodoro-10s", now: Date(timeIntervalSince1970: 91))

        XCTAssertNotNil(coordinator.activePomodoro)
        XCTAssertEqual(coordinator.sessions.first?.title, "Pomodoro focus")
    }

    func testActionRunsThroughAdapterAndRecordsActivity() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 100))

        coordinator.performAction(id: "codex")

        XCTAssertEqual(coordinator.agents.first(where: { $0.id == "codex" })?.status, .running)
        XCTAssertEqual(coordinator.recentActivities.first?.title, "Started Codex")
        XCTAssertEqual(coordinator.recentActivities.first?.detail, "C++ core marked Codex as running")
        XCTAssertEqual(coordinator.sessions.first?.status, .running)
    }

    func testHoverExitCollapsesImmediately() {
        let start = Date(timeIntervalSince1970: 200)
        let coordinator = TaskCoordinator(now: start)

        coordinator.pointerEntered()
        XCTAssertTrue(coordinator.isExpanded)

        coordinator.pointerExited(at: start)

        XCTAssertFalse(coordinator.isExpanded)
    }

    func testPomodoroStartCancelAndCompletionReminder() {
        let start = Date(timeIntervalSince1970: 300)
        let coordinator = TaskCoordinator(now: start)

        coordinator.startPomodoro(duration: 60, now: start)
        XCTAssertNotNil(coordinator.activePomodoro)
        XCTAssertEqual(coordinator.sessions.first?.title, "Pomodoro focus")

        coordinator.cancelPomodoro(now: start.addingTimeInterval(10))
        XCTAssertNil(coordinator.activePomodoro)
        XCTAssertEqual(coordinator.recentActivities.first?.title, "Pomodoro cancelled")
        XCTAssertEqual(coordinator.recentActivities.first?.detail, "Focus session stopped in C++ core")

        coordinator.startPomodoro(duration: 60, now: start)
        coordinator.advanceTime(to: start.addingTimeInterval(60))

        XCTAssertNil(coordinator.activePomodoro)
        XCTAssertEqual(coordinator.pendingNotifications.first?.title, "Pomodoro complete")
        XCTAssertEqual(coordinator.recentActivities.first?.title, "Pomodoro complete")
        XCTAssertEqual(coordinator.recentActivities.first?.detail, "Reminder request created in C++ core")
    }
}
