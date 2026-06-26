import XCTest
@testable import JunimoCore

final class TaskCoordinatorTests: XCTestCase {
    private final class FakeCodexRunner: CodexCommandRunning {
        var results: [[String]: CodexCommandResult]

        init(results: [[String]: CodexCommandResult]) {
            self.results = results
        }

        func runCodex(arguments: [String], timeout: TimeInterval) throws -> CodexCommandResult {
            guard let result = results[arguments] else {
                throw CodexStatusProviderError.commandFailed(arguments.joined(separator: " "))
            }
            return result
        }
    }

    private struct FakeAppServerClient: CodexAppServerQuerying {
        var snapshot: CodexAppServerSnapshot?

        func querySnapshot(timeout: TimeInterval, now: Date) -> CodexAppServerSnapshot? {
            snapshot
        }
    }

    func testPreferencesComeFromCoreAndUpdateLayoutValues() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 80))

        XCTAssertEqual(coordinator.preferences.accent, .mint)
        XCTAssertEqual(coordinator.preferences.expandedWidth, 760)
        XCTAssertEqual(coordinator.preferences.expandedHeight, 300)

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
        XCTAssertEqual(coordinator.codexMonitor.activeThreadCount, 1)
        XCTAssertEqual(coordinator.codexMonitor.threads.first?.id, "junimo-local-codex")
        XCTAssertEqual(coordinator.recentActivities.first?.title, "Started Codex")
        XCTAssertEqual(coordinator.recentActivities.first?.detail, "C++ core marked Codex as running")
        XCTAssertEqual(coordinator.sessions.first?.status, .running)
    }

    func testCodexMonitorDocumentsSupportedStatusSources() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 120))

        XCTAssertEqual(coordinator.codexMonitor.usage.status, .needsSetup)
        XCTAssertTrue(coordinator.codexMonitor.usage.detail.contains("account/rateLimits/read"))
        XCTAssertTrue(coordinator.codexMonitor.findings.contains(where: { $0.id == "exec-json" && $0.status == .available }))
        XCTAssertTrue(coordinator.codexMonitor.findings.contains(where: { $0.id == "app-server" && $0.detail.contains("thread/list") }))
    }

    func testCodexThreadCompletionRequestsNotification() {
        let start = Date(timeIntervalSince1970: 130)
        let coordinator = TaskCoordinator(now: start)

        coordinator.updateCodexThread(
            id: "thread-1",
            title: "Fix build",
            status: .running,
            detail: "Codex is editing files",
            now: start
        )
        coordinator.updateCodexThread(
            id: "thread-1",
            title: "Fix build",
            status: .completed,
            detail: "Tests passed",
            now: start.addingTimeInterval(60)
        )

        XCTAssertEqual(coordinator.codexMonitor.activeThreadCount, 0)
        XCTAssertEqual(coordinator.codexMonitor.threads.first?.status, .completed)
        XCTAssertEqual(coordinator.pendingNotifications.first?.title, "Codex thread complete")
        XCTAssertEqual(coordinator.recentActivities.first?.title, "Codex thread complete")
        XCTAssertEqual(coordinator.agents.first(where: { $0.id == "codex" })?.status, .succeeded)
    }

    func testCodexMonitorRefreshCompletesMissingActiveThreads() {
        let start = Date(timeIntervalSince1970: 140)
        let coordinator = TaskCoordinator(now: start)
        coordinator.updateCodexThread(
            id: "thread-2",
            title: "Review diff",
            status: .running,
            detail: "Codex is reviewing",
            now: start
        )

        coordinator.refreshCodexMonitor(
            CodexMonitorSnapshot(
                usage: coordinator.codexMonitor.usage,
                threads: [],
                findings: coordinator.codexMonitor.findings,
                refreshedAt: start.addingTimeInterval(30)
            ),
            now: start.addingTimeInterval(30)
        )

        XCTAssertEqual(coordinator.codexMonitor.activeThreadCount, 0)
        XCTAssertEqual(coordinator.codexMonitor.threads.first?.status, .completed)
        XCTAssertEqual(coordinator.pendingNotifications.first?.title, "Codex thread complete")
    }

    func testCodexCLIStatusProviderParsesDoctorAndCloudTaskJSON() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = CodexCLIStatusProvider(
            runner: FakeCodexRunner(
                results: [
                    ["doctor", "--json"]: CodexCommandResult(exitCode: 1, stdout: Self.doctorJSON, stderr: ""),
                    ["cloud", "list", "--json", "--limit", "20"]: CodexCommandResult(exitCode: 0, stdout: Self.cloudJSON, stderr: "")
                ]
            ),
            appServerClient: nil
        )

        let snapshot = provider.loadSnapshot(now: now)

        XCTAssertEqual(snapshot.usage.status, .needsSetup)
        XCTAssertTrue(snapshot.usage.detail.contains("chatgpt"))
        XCTAssertEqual(snapshot.threads.count, 2)
        XCTAssertEqual(snapshot.threads.first?.status, .running)
        XCTAssertTrue(snapshot.findings.contains(where: { $0.id == "auth" && $0.status == .available }))
        XCTAssertTrue(snapshot.findings.contains(where: { $0.id == "network" && $0.status == .degraded }))
    }

    func testCodexCLIStatusProviderMergesAppServerQuotaAndThreads() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = CodexCLIStatusProvider(
            runner: FakeCodexRunner(
                results: [
                    ["doctor", "--json"]: CodexCommandResult(exitCode: 0, stdout: Self.doctorJSON, stderr: ""),
                    ["cloud", "list", "--json", "--limit", "20"]: CodexCommandResult(exitCode: 0, stdout: Self.cloudJSON, stderr: "")
                ]
            ),
            appServerClient: FakeAppServerClient(
                snapshot: CodexStatusParser.appServerSnapshot(fromJSONL: Self.appServerJSONL, now: now)
            )
        )

        let snapshot = provider.loadSnapshot(now: now)

        XCTAssertEqual(snapshot.usage.status, .available)
        XCTAssertEqual(snapshot.usage.summaryText, "28% left")
        XCTAssertTrue(snapshot.threads.contains(where: { $0.id == "local:thread_local_1" && $0.status == .waiting }))
        XCTAssertTrue(snapshot.threads.contains(where: { $0.id == "cloud:task_1" && $0.status == .running }))
        XCTAssertTrue(snapshot.findings.contains(where: { $0.id == "app-server-rate-limits" && $0.status == .available }))
        XCTAssertTrue(snapshot.findings.contains(where: { $0.id == "app-server-threads" && $0.status == .available }))
    }

    func testCodexStatusParserParsesAppServerRateLimits() {
        let usage = CodexStatusParser.usageSnapshot(fromAppServerRateLimitsJSON: Self.rateLimitsJSON)

        XCTAssertEqual(usage?.status, .available)
        XCTAssertEqual(usage?.planLabel, "Plus")
        XCTAssertEqual(usage?.primaryWindow?.usedPercent, 72)
        XCTAssertEqual(usage?.primaryWindow?.durationMinutes, 300)
        XCTAssertEqual(usage?.summaryText, "28% left")
        XCTAssertEqual(usage?.creditsBalance, "$3.10")
    }

    func testHoverExitCollapsesImmediately() {
        let start = Date(timeIntervalSince1970: 200)
        let coordinator = TaskCoordinator(now: start)

        coordinator.pointerEntered()
        XCTAssertTrue(coordinator.isExpanded)

        coordinator.pointerExited(at: start)

        XCTAssertFalse(coordinator.isExpanded)
    }

    func testCornerNoteEditsTodosAndExpansionState() {
        let coordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 210))

        XCTAssertFalse(coordinator.isCornerNoteExpanded)
        coordinator.setCornerNoteExpanded(true)
        coordinator.updateCornerNoteText("Ship the corner note")
        coordinator.addCornerTodo(title: "Write tests")

        let todo = coordinator.cornerTodos.last
        XCTAssertTrue(coordinator.isCornerNoteExpanded)
        XCTAssertEqual(coordinator.cornerNoteText, "Ship the corner note")
        XCTAssertEqual(todo?.title, "Write tests")

        if let id = todo?.id {
            coordinator.updateCornerTodo(id: id, title: "Run tests")
            coordinator.toggleCornerTodo(id: id)
            XCTAssertEqual(coordinator.cornerTodos.last?.title, "Run tests")
            XCTAssertEqual(coordinator.cornerTodos.last?.isDone, true)

            coordinator.removeCornerTodo(id: id)
            XCTAssertFalse(coordinator.cornerTodos.contains(where: { $0.id == id }))
        }

        coordinator.setCornerNoteExpanded(false)
        XCTAssertFalse(coordinator.isCornerNoteExpanded)
    }

    private static let doctorJSON = """
    {
      "overallStatus": "fail",
      "codexVersion": "0.137.0",
      "checks": {
        "auth.credentials": {
          "status": "ok",
          "summary": "auth is configured",
          "details": { "stored auth mode": "chatgpt" }
        },
        "app_server.status": {
          "status": "ok",
          "summary": "background server is not running",
          "details": { "status": "not running" }
        },
        "state.rollout_db_parity": {
          "status": "ok",
          "summary": "rollout files and state DB thread inventory agree"
        },
        "network.provider_reachability": {
          "status": "fail",
          "summary": "one or more required provider endpoints are unreachable over HTTP"
        }
      }
    }
    """

    private static let cloudJSON = """
    {
      "tasks": [
        {
          "id": "task_1",
          "title": "Fix flaky test",
          "status": "running",
          "updated_at": "2026-06-25T16:35:06Z",
          "environment_label": "Junimo",
          "summary": "Editing files"
        },
        {
          "id": "task_2",
          "title": "Review diff",
          "status": "completed",
          "updated_at": "2026-06-25T16:30:00Z",
          "environment_label": "Junimo",
          "summary": "Done"
        }
      ],
      "cursor": null
    }
    """

    private static let rateLimitsJSON = """
    {
      "rateLimits": {
        "planType": "plus",
        "primary": {
          "usedPercent": 72,
          "resetsAt": 1800000300,
          "windowDurationMins": 300
        },
        "secondary": {
          "usedPercent": 40,
          "windowDurationMins": 10080
        },
        "credits": {
          "hasCredits": true,
          "unlimited": false,
          "balance": "$3.10"
        }
      }
    }
    """

    private static let appServerJSONL = """
    {"id":0,"result":{"codexHome":"/Users/test/.codex","platformFamily":"unix","platformOs":"macos","userAgent":"codex-test"}}
    {"id":1,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":72,"resetsAt":1800000300,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"$3.10"}}}}
    {"id":2,"result":{"data":[{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_1","modelProvider":"openai","name":"Fix local build","preview":"Fix local build","sessionId":"session_1","source":{"type":"cli"},"status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[],"updatedAt":1800000100}]}}
    """

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
