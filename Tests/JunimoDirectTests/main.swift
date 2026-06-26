import Foundation
import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

final class FakeCodexRunner: CodexCommandRunning {
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

struct FakeAppServerClient: CodexAppServerQuerying {
    var snapshot: CodexAppServerSnapshot?

    func querySnapshot(timeout: TimeInterval, now: Date) -> CodexAppServerSnapshot? {
        snapshot
    }
}

let actionCoordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 100))
expect(actionCoordinator.preferences.accent == .mint, "Preferences should default from C++ core")
expect(actionCoordinator.preferences.expandedWidth == 760, "Comfortable panel width should come from C++ core")
expect(actionCoordinator.preferences.expandedHeight == 300, "Comfortable panel height should come from C++ core")
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
expect(actionCoordinator.codexMonitor.activeThreadCount == 1, "Codex monitor should track local running thread")
expect(actionCoordinator.codexMonitor.threads.first?.id == "junimo-local-codex", "Codex monitor should record Junimo launched thread")
expect(actionCoordinator.recentActivities.first?.title == "Started Codex", "Action should record activity")
expect(actionCoordinator.recentActivities.first?.detail == "C++ core marked Codex as running", "Action should be backed by C++ core")
expect(actionCoordinator.sessions.first?.status == .running, "Agent action should create running session")

let codexStart = Date(timeIntervalSince1970: 130)
let codexCoordinator = TaskCoordinator(now: codexStart)
expect(codexCoordinator.codexMonitor.usage.status == .needsSetup, "Codex quota should require app-server setup by default")
expect(codexCoordinator.codexMonitor.usage.detail.contains("account/rateLimits/read"), "Codex quota source should name app-server rate-limit method")
expect(codexCoordinator.codexMonitor.findings.contains(where: { $0.id == "exec-json" && $0.status == .available }), "Codex exec JSON should be recorded as available")
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .running,
    detail: "Codex is editing files",
    now: codexStart
)
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .completed,
    detail: "Tests passed",
    now: codexStart.addingTimeInterval(60)
)
expect(codexCoordinator.codexMonitor.activeThreadCount == 0, "Completed Codex thread should no longer be active")
expect(codexCoordinator.pendingNotifications.first?.title == "Codex thread complete", "Completed Codex thread should request notification")
expect(codexCoordinator.recentActivities.first?.title == "Codex thread complete", "Completed Codex thread should record activity")

let codexRefreshCoordinator = TaskCoordinator(now: codexStart)
codexRefreshCoordinator.updateCodexThread(
    id: "thread-2",
    title: "Review diff",
    status: .running,
    detail: "Codex is reviewing",
    now: codexStart
)
codexRefreshCoordinator.refreshCodexMonitor(
    CodexMonitorSnapshot(
        usage: codexRefreshCoordinator.codexMonitor.usage,
        threads: [],
        findings: codexRefreshCoordinator.codexMonitor.findings,
        refreshedAt: codexStart.addingTimeInterval(30)
    ),
    now: codexStart.addingTimeInterval(30)
)
expect(codexRefreshCoordinator.codexMonitor.activeThreadCount == 0, "Missing active thread should complete on refresh")
expect(codexRefreshCoordinator.codexMonitor.threads.first?.status == .completed, "Missing active thread should be retained as completed")
expect(codexRefreshCoordinator.pendingNotifications.first?.title == "Codex thread complete", "Missing active thread should request completion notification")

let doctorJSON = """
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

let cloudJSON = """
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

let provider = CodexCLIStatusProvider(
    runner: FakeCodexRunner(
        results: [
            ["doctor", "--json"]: CodexCommandResult(exitCode: 1, stdout: doctorJSON, stderr: ""),
            ["cloud", "list", "--json", "--limit", "20"]: CodexCommandResult(exitCode: 0, stdout: cloudJSON, stderr: "")
        ]
    ),
    appServerClient: nil
)
let providerSnapshot = provider.loadSnapshot(now: Date(timeIntervalSince1970: 1_800_000_000))
expect(providerSnapshot.usage.status == .needsSetup, "Provider should mark quota as needing app-server setup")
expect(providerSnapshot.usage.detail.contains("chatgpt"), "Provider should describe current Codex auth mode")
expect(providerSnapshot.threads.count == 2, "Provider should load cloud tasks")
expect(providerSnapshot.threads.first?.status == .running, "Provider should map running cloud task status")
expect(providerSnapshot.findings.contains(where: { $0.id == "auth" && $0.status == .available }), "Provider should expose auth finding")
expect(providerSnapshot.findings.contains(where: { $0.id == "network" && $0.status == .degraded }), "Provider should expose degraded network finding")

let rateLimitsJSON = """
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
let usage = CodexStatusParser.usageSnapshot(fromAppServerRateLimitsJSON: rateLimitsJSON)
expect(usage?.status == .available, "Rate limit parser should mark app-server quota as available")
expect(usage?.planLabel == "Plus", "Rate limit parser should expose plan label")
expect(usage?.primaryWindow?.usedPercent == 72, "Rate limit parser should parse primary used percent")
expect(usage?.primaryWindow?.durationMinutes == 300, "Rate limit parser should parse 5-hour window duration")
expect(usage?.summaryText == "28% left", "Rate limit parser should compute remaining percentage")
expect(usage?.creditsBalance == "$3.10", "Rate limit parser should parse credits balance")

let appServerJSONL = """
{"id":0,"result":{"codexHome":"/Users/test/.codex","platformFamily":"unix","platformOs":"macos","userAgent":"codex-test"}}
{"id":1,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":72,"resetsAt":1800000300,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"$3.10"}}}}
{"id":2,"result":{"data":[{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_1","modelProvider":"openai","name":"Fix local build","preview":"Fix local build","sessionId":"session_1","source":{"type":"cli"},"status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[],"updatedAt":1800000100}]}}
"""
let appServerProvider = CodexCLIStatusProvider(
    runner: FakeCodexRunner(
        results: [
            ["doctor", "--json"]: CodexCommandResult(exitCode: 0, stdout: doctorJSON, stderr: ""),
            ["cloud", "list", "--json", "--limit", "20"]: CodexCommandResult(exitCode: 0, stdout: cloudJSON, stderr: "")
        ]
    ),
    appServerClient: FakeAppServerClient(
        snapshot: CodexStatusParser.appServerSnapshot(
            fromJSONL: appServerJSONL,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
    )
)
let appServerSnapshot = appServerProvider.loadSnapshot(now: Date(timeIntervalSince1970: 1_800_000_000))
expect(appServerSnapshot.usage.status == .available, "App-server provider should prefer live quota")
expect(appServerSnapshot.usage.summaryText == "28% left", "App-server provider should expose remaining quota")
expect(appServerSnapshot.threads.contains(where: { $0.id == "local:thread_local_1" && $0.status == .waiting }), "App-server provider should load local waiting thread")
expect(appServerSnapshot.threads.contains(where: { $0.id == "cloud:task_1" && $0.status == .running }), "App-server provider should keep cloud running task")
expect(appServerSnapshot.findings.contains(where: { $0.id == "app-server-rate-limits" && $0.status == .available }), "App-server quota finding should be available")
expect(appServerSnapshot.findings.contains(where: { $0.id == "app-server-threads" && $0.status == .available }), "App-server thread finding should be available")

let hoverStart = Date(timeIntervalSince1970: 200)
let hoverCoordinator = TaskCoordinator(now: hoverStart)
hoverCoordinator.pointerEntered()
expect(hoverCoordinator.isExpanded, "Console should expand on hover")
hoverCoordinator.pointerExited(at: hoverStart)
expect(!hoverCoordinator.isExpanded, "Console should collapse immediately after hover exit")

let cornerCoordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 210))
expect(!cornerCoordinator.isCornerNoteExpanded, "Corner note should start collapsed")
cornerCoordinator.setCornerNoteExpanded(true)
cornerCoordinator.updateCornerNoteText("Ship the corner note")
cornerCoordinator.addCornerTodo(title: "Write tests")
let cornerTodo = cornerCoordinator.cornerTodos.last
expect(cornerCoordinator.isCornerNoteExpanded, "Corner note should expand")
expect(cornerCoordinator.cornerNoteText == "Ship the corner note", "Corner note text should update")
expect(cornerTodo?.title == "Write tests", "Corner todo should be added")
if let cornerTodoID = cornerTodo?.id {
    cornerCoordinator.updateCornerTodo(id: cornerTodoID, title: "Run tests")
    cornerCoordinator.toggleCornerTodo(id: cornerTodoID)
    expect(cornerCoordinator.cornerTodos.last?.title == "Run tests", "Corner todo title should update")
    expect(cornerCoordinator.cornerTodos.last?.isDone == true, "Corner todo should toggle done")
    cornerCoordinator.removeCornerTodo(id: cornerTodoID)
    expect(!cornerCoordinator.cornerTodos.contains(where: { $0.id == cornerTodoID }), "Corner todo should be removed")
}
cornerCoordinator.setCornerNoteExpanded(false)
expect(!cornerCoordinator.isCornerNoteExpanded, "Corner note should collapse")

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
