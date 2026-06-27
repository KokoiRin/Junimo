import Foundation
import Combine
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

final class FakePomodoroCore: PomodoroCore, ConsoleStateCore {
    private var active: PomodoroSession?

    /// 业务语义：fake core 用真实时间边界创建 active timer，支撑 PomodoroFeature effect 测试。
    func start(duration: TimeInterval, at date: Date) {
        active = PomodoroSession(startedAt: date, duration: duration)
    }

    /// 业务语义：fake core 取消时只清理 active timer，不产生 completion effect。
    func cancel(at date: Date) -> CppPomodoroResult {
        guard active != nil else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        active = nil
        return CppPomodoroResult(changed: true, completed: false, activityTitle: "Pomodoro cancelled", activityDetail: "Focus session stopped", notificationTitle: "", notificationBody: "")
    }

    /// 业务语义：fake core 只有到达结束时间才报告 completion，避免 fallback 行为削弱测试语义。
    func advanceTime(to date: Date) -> CppPomodoroResult {
        guard let current = active else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        guard date >= current.endsAt else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        active = nil
        return CppPomodoroResult(
            changed: true,
            completed: true,
            activityTitle: "Pomodoro complete",
            activityDetail: "Reminder is ready",
            notificationTitle: "Pomodoro complete",
            notificationBody: "Focus session finished."
        )
    }

    /// 业务语义：PomodoroFeature 测试不关心 agents，fake core 返回空投影。
    func agents() -> [AgentSummary] { [] }

    /// 业务语义：PomodoroFeature 测试不关心 actions，fake core 返回空投影。
    func actions() -> [ConsoleAction] { [] }

    /// 业务语义：PomodoroFeature 测试不关心 activity feed，fake core 返回空投影。
    func recentActivities() -> [ActivityEntry] { [] }

    /// 业务语义：active Pomodoro projection 是这个 fake core 的唯一测试状态。
    func activePomodoro() -> PomodoroSession? { active }

    /// 业务语义：PomodoroFeature 不记录 activity，fake core 忽略外部记录请求。
    func recordActivity(title: String, detail: String, at date: Date) {}
}

guard let consoleFeatureCore = CppBackedCore() else {
    fputs("Test failed: C++ core should be available for ConsoleFeature smoke test\n", stderr)
    exit(1)
}
var consoleFeature = ConsoleFeature(core: consoleFeatureCore)
expect(consoleFeature.projectProfile.name == "Junimo", "ConsoleFeature should expose project profile from core")
expect(consoleFeature.commandResults.count >= 6, "ConsoleFeature should expose default command results")
consoleFeature.updateCommandQuery("focus")
// 业务语义：ConsoleFeature 是 command query/results 的 owner，查询变化只能刷新 command 投影。
expect(consoleFeature.commandResults.contains(where: { $0.id == "pomodoro-25" }), "ConsoleFeature should refresh matching command results")
let consoleEffects = consoleFeature.performAction(id: "codex", now: Date(timeIntervalSince1970: 95))
// 业务语义：ConsoleFeature 执行动作后刷新 console 投影，并把 running agent 暴露成 effect。
expect(consoleEffects.agentStarts.first?.agentID == "codex", "ConsoleFeature should emit running agent start effect")
expect(consoleFeature.agents.first(where: { $0.id == "codex" })?.status == .running, "ConsoleFeature should refresh agent status")
expect(consoleFeature.recentActivities.first?.title == "Started Codex", "ConsoleFeature should refresh recent activity")
expect(consoleFeature.sessions.first?.status == .running, "ConsoleFeature should refresh sessions after action")

var preferencesFeature = PreferencesFeature(core: SwiftFallbackCore())
// 业务语义：PreferencesFeature 是 UI preferences/theme 的 Swift 投影 owner，初始化必须来自 core snapshot。
expect(preferencesFeature.preferences.accent == .mint, "PreferencesFeature should expose default accent")
expect(preferencesFeature.theme.accent == .mint, "PreferencesFeature theme should match default accent")
preferencesFeature.setDensity(.compact)
expect(preferencesFeature.preferences.density == .compact, "PreferencesFeature should update density through core")
expect(preferencesFeature.preferences.expandedWidth == 700, "PreferencesFeature should expose compact width from core")
preferencesFeature.setAccent(.amber)
expect(preferencesFeature.preferences.accent == .amber, "PreferencesFeature should update accent through core")
expect(preferencesFeature.theme.accent == .amber, "PreferencesFeature theme should track accent")

let actionCoordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 100))
expect(actionCoordinator.preferences.accent == .mint, "Preferences should default from C++ core")
expect(actionCoordinator.preferences.expandedWidth == 760, "Comfortable panel width should come from C++ core")
expect(actionCoordinator.preferences.expandedHeight == 300, "Comfortable panel height should come from C++ core")
actionCoordinator.setDensity(.compact)
expect(actionCoordinator.preferences.density == .compact, "Density should update through C++ core")
expect(actionCoordinator.preferences.expandedWidth == 700, "Compact panel width should come from C++ core")
actionCoordinator.setAccent(.amber)
expect(actionCoordinator.theme.accent == .amber, "Accent should update theme through C++ core")
var layoutPreferenceUpdates = 0
actionCoordinator.layoutPreferencesDidChange = { updated in
    layoutPreferenceUpdates += 1
    expect(updated.density == .comfortable, "Layout callback should receive updated density")
}
actionCoordinator.setDensity(.comfortable)
expect(layoutPreferenceUpdates == 1, "Coordinator preferences compatibility path should still notify layout")
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
// 业务语义：Junimo 是外部 Codex 状态中心，Codex action 不能伪造本地 running thread。
expect(actionCoordinator.codexMonitor.activeThreadCount == 0, "Codex action should not fake an active thread")
expect(!actionCoordinator.codexMonitor.threads.contains { $0.id == "junimo-local-codex" }, "Codex action should not create a placeholder thread")
expect(actionCoordinator.codexCollapsedStatusText == "Needs setup", "Collapsed status should remain adapter/quota based without observed work")
expect(actionCoordinator.recentActivities.first?.title == "Started Codex", "Action should record activity")
expect(actionCoordinator.recentActivities.first?.detail == "C++ core marked Codex as running", "Action should be backed by C++ core")
expect(actionCoordinator.sessions.first?.status == .running, "Agent action should create running session")

let codexStart = Date(timeIntervalSince1970: 130)
var codexFeature = CodexFeature(now: codexStart)
expect(codexFeature.collapsedStatusText == "Needs setup", "CodexFeature should expose default quota/setup status")
let codexFeatureRunningEffects = codexFeature.updateThread(
    id: "feature-thread-1",
    title: "Fix build",
    status: .running,
    detail: "Codex is editing files",
    now: codexStart
)
// 业务语义：CodexFeature 是 Codex 生命周期状态的唯一 owner，运行态应从 feature projection 暴露。
expect(codexFeatureRunningEffects.isEmpty, "Running Codex thread should not request terminal effects")
expect(codexFeature.monitor.activeThreadCount == 1, "CodexFeature should track running lifecycle state")
expect(codexFeature.collapsedStatusText == "Codex running", "CodexFeature should prioritize running status text")
let codexFeatureCompletionEffects = codexFeature.updateThread(
    id: "feature-thread-1",
    title: "Fix build",
    status: .completed,
    detail: "Tests passed",
    now: codexStart.addingTimeInterval(60)
)
expect(codexFeature.monitor.activeThreadCount == 0, "CodexFeature should remove completed work from active count")
expect(codexFeature.reviewItems.first?.threadID == "feature-thread-1", "CodexFeature should create review item for terminal transition")
expect(codexFeature.collapsedStatusText == "Codex done", "CodexFeature should expose review cue before quota text")
expect(codexFeature.reviewItems.first?.attentionCue.tone == .completed, "Completed review should expose completed attention tone")
expect(codexFeature.reviewItems.first?.attentionCue.symbolName == "checkmark.seal.fill", "Completed review should expose celebratory symbol")
expect(codexFeatureCompletionEffects.notifications.first?.title == "Codex thread complete", "CodexFeature should request completion notification effect")
expect(codexFeatureCompletionEffects.activities.first?.title == "Codex thread complete", "CodexFeature should request completion activity effect")
codexFeature.acknowledgeLatestReview()
expect(codexFeature.reviewItems.isEmpty, "CodexFeature should clear latest review by intent")

let codexCoordinator = TaskCoordinator(now: codexStart)
expect(codexCoordinator.codexMonitor.usage.status == .needsSetup, "Codex quota should require app-server setup by default")
expect(codexCoordinator.codexMonitor.usage.detail.contains("account/rateLimits/read"), "Codex quota source should name app-server rate-limit method")
expect(codexCoordinator.codexMonitor.findings.contains(where: { $0.id == "exec-json" && $0.status == .available }), "Codex exec JSON should be recorded as available")
expect(codexCoordinator.codexCollapsedStatusText == "Needs setup", "Collapsed status should show quota/setup text before activity")
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .running,
    detail: "Codex is editing files",
    now: codexStart
)
// 业务语义：Codex 正在运行时，collapsed 刘海右侧应该直接暴露 running，而不是藏在展开态。
expect(codexCoordinator.codexCollapsedStatusText == "Codex running", "Collapsed status should show running Codex work")
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .waiting,
    detail: "Codex is waiting for input",
    now: codexStart.addingTimeInterval(30)
)
// 业务语义：Codex 等待输入或审批时，collapsed 刘海右侧应该直接暴露 waiting。
expect(codexCoordinator.codexCollapsedStatusText == "Codex waiting", "Collapsed status should show waiting Codex work")
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
expect(codexCoordinator.codexReviewItems.first?.threadID == "thread-1", "Completed Codex thread should create review item")
expect(codexCoordinator.codexReviewItems.first?.status == .completed, "Codex review item should keep completed status")
// 业务语义：Codex 完成后 collapsed 刘海需要显示明确的完成提示，而不是继续只显示配额。
expect(codexCoordinator.codexReviewItems.first?.cueText == "Codex done", "Completed Codex review item should expose a collapsed cue")
expect(codexCoordinator.codexCollapsedStatusText == "Codex done", "Collapsed status should prioritize completed review cue")
var codexPublishCount = 0
let codexPublishCancellable = codexCoordinator.objectWillChange.sink {
    codexPublishCount += 1
}
if let deliveredNotificationID = codexCoordinator.pendingNotifications.first?.id {
    codexCoordinator.markNotificationDelivered(id: deliveredNotificationID)
}
expect(codexPublishCount > 0, "Codex notification delivery should publish UI changes")
expect(codexCoordinator.pendingNotifications.isEmpty, "Delivered notification should leave delivery queue")
expect(codexCoordinator.codexReviewItems.count == 1, "Codex review item should remain after notification delivery")
codexPublishCount = 0
codexCoordinator.acknowledgeLatestCodexReview()
expect(codexPublishCount > 0, "Codex review acknowledgement should publish UI changes")
expect(codexCoordinator.codexReviewItems.isEmpty, "Acknowledged Codex review item should clear")
_ = codexPublishCancellable

codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .running,
    detail: "Codex is editing files again",
    now: codexStart.addingTimeInterval(120)
)
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .failed,
    detail: "Build failed",
    now: codexStart.addingTimeInterval(180)
)
expect(codexCoordinator.codexReviewItems.first?.status == .failed, "Failed Codex thread should create review item")
// 业务语义：Codex 失败后 collapsed 刘海需要显示失败提示，并沿用待处理 review 状态。
expect(codexCoordinator.codexReviewItems.first?.cueText == "Codex failed", "Failed Codex review item should expose a collapsed cue")
expect(codexCoordinator.codexReviewItems.first?.attentionCue.tone == .failed, "Failed review should expose failed attention tone")
expect(codexCoordinator.codexReviewItems.first?.attentionCue.symbolName == "exclamationmark.triangle.fill", "Failed review should expose warning symbol")
codexCoordinator.updateCodexThread(
    id: "thread-1",
    title: "Fix build",
    status: .running,
    detail: "Retry started",
    now: codexStart.addingTimeInterval(240)
)
expect(codexCoordinator.codexReviewItems.isEmpty, "Active retry should clear stale Codex review item")

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
expect(codexRefreshCoordinator.codexMonitor.activeThreadCount == 1, "Missing active thread should stay active until an explicit terminal event arrives")
expect(codexRefreshCoordinator.codexMonitor.threads.first?.status == .running, "Missing active thread should not be marked completed by snapshot absence")
expect(codexRefreshCoordinator.pendingNotifications.isEmpty, "Snapshot absence should not request a completion notification")
expect(codexRefreshCoordinator.codexReviewItems.isEmpty, "Snapshot absence should not create a review item")

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
{"id":2,"result":{"data":[{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_1","modelProvider":"openai","name":"Fix local build","preview":"Fix local build","sessionId":"session_1","source":{"type":"cli"},"status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[],"updatedAt":1800000100},{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_2","modelProvider":"openai","name":"Open local review","preview":"Open local review","sessionId":"session_2","source":{"type":"cli"},"status":{"type":"notLoaded"},"turns":[],"updatedAt":1800000090},{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_3","modelProvider":"openai","name":"Idle local review","preview":"Idle local review","sessionId":"session_3","source":{"type":"cli"},"status":{"type":"idle"},"turns":[],"updatedAt":1800000080},{"cliVersion":"0.137.0","createdAt":1799990000,"cwd":"/Users/test/repo","ephemeral":false,"id":"thread_local_4","modelProvider":"openai","name":"Unknown local review","preview":"Unknown local review","sessionId":"session_4","source":{"type":"cli"},"status":{"type":"pausedByProtocol"},"turns":[],"updatedAt":1800000070}]}}
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
expect(appServerSnapshot.threads.contains(where: { $0.id == "local:thread_local_2" && $0.status == .open }), "App-server provider should keep notLoaded local threads as open work")
expect(appServerSnapshot.threads.contains(where: { $0.id == "local:thread_local_3" && $0.status == .open }), "App-server provider should keep idle non-archived local threads as open work")
expect(appServerSnapshot.threads.contains(where: { $0.id == "local:thread_local_4" && $0.status == .open }), "App-server provider should keep unknown non-terminal statuses as open work")
expect(appServerSnapshot.openThreadCount == 3, "App-server provider should count open local threads before UI truncation")
expect(appServerSnapshot.threads.contains(where: { $0.id == "cloud:task_1" && $0.status == .running }), "App-server provider should keep cloud running task")
expect(appServerSnapshot.findings.contains(where: { $0.id == "app-server-rate-limits" && $0.status == .available }), "App-server quota finding should be available")

let completedWithOpenCoordinator = TaskCoordinator(now: codexStart)
completedWithOpenCoordinator.refreshCodexMonitor(
    CodexMonitorSnapshot(
        usage: completedWithOpenCoordinator.codexMonitor.usage,
        threads: [
            CodexThreadSummary(id: "local:open-thread", title: "Open review", status: .open, detail: "open local conversation", updatedAt: codexStart),
            CodexThreadSummary(id: "local:finished-thread", title: "Finished review", status: .running, detail: "running local conversation", updatedAt: codexStart.addingTimeInterval(-1))
        ],
        findings: completedWithOpenCoordinator.codexMonitor.findings,
        refreshedAt: codexStart
    )
)
completedWithOpenCoordinator.applyCodexRealtimeEvent(
    .thread(
        CodexThreadSummary(
            id: "local:finished-thread",
            title: "Finished review",
            status: .completed,
            detail: "completed explicitly",
            updatedAt: codexStart.addingTimeInterval(5)
        )
    ),
    now: codexStart.addingTimeInterval(5)
)
completedWithOpenCoordinator.acknowledgeLatestCodexReview()
expect(completedWithOpenCoordinator.codexCollapsedStatusText == "Codex open 1", "Collapsed status should show remaining open Codex work after a different thread completes")

let manyThreads = (0..<12).map { index in
    CodexThreadSummary(
        id: "local:thread-\(index)",
        title: "Thread \(index)",
        status: index == 11 ? .open : .idle,
        detail: "fixture",
        updatedAt: codexStart.addingTimeInterval(Double(100 - index))
    )
}
let truncationCoordinator = TaskCoordinator(now: codexStart)
truncationCoordinator.refreshCodexMonitor(
    CodexMonitorSnapshot(
        usage: truncationCoordinator.codexMonitor.usage,
        threads: manyThreads,
        findings: truncationCoordinator.codexMonitor.findings,
        refreshedAt: codexStart
    )
)
expect(truncationCoordinator.codexMonitor.threads.count == 8, "Visible Codex thread list should remain bounded")
expect(truncationCoordinator.codexMonitor.openThreadCount == 1, "Open thread count should be computed before visible list truncation")
expect(truncationCoordinator.codexCollapsedStatusText == "Codex open 1", "Collapsed status should include open work even when it is older than the visible list")
expect(appServerSnapshot.findings.contains(where: { $0.id == "app-server-threads" && $0.status == .available }), "App-server thread finding should be available")

let realtimeJSONL = """
{"method":"account/rateLimitsUpdated","params":{"rateLimits":{"planType":"plus","primary":{"usedPercent":64,"resetsAt":1800000600,"windowDurationMins":300},"secondary":{"usedPercent":25,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"$4.20"}}}}
{"method":"thread/statusChanged","params":{"thread":{"id":"thread_realtime_1","name":"Realtime fix","cwd":"/Users/test/repo","modelProvider":"openai","status":{"type":"active","activeFlags":["waitingOnUser"]},"updatedAt":1800000200}}}
"""
let realtimeEvents = CodexRealtimeEventParser.appServerEvents(
    fromJSONL: realtimeJSONL,
    now: Date(timeIntervalSince1970: 1_800_000_100)
)
expect(realtimeEvents.contains(where: { event in
    if case let .usage(usage) = event {
        return usage.summaryText == "36% left" && usage.creditsBalance == "$4.20"
    }
    return false
}), "Realtime parser should emit rate-limit usage updates")
expect(realtimeEvents.contains(where: { event in
    if case let .thread(thread) = event {
        return thread.id == "local:thread_realtime_1" && thread.status == .waiting && thread.title == "Realtime fix"
    }
    return false
}), "Realtime parser should emit app-server thread updates")

let execJSONL = """
{"type":"thread.started","thread_id":"exec_thread_1","title":"Run tests"}
{"type":"turn.started","thread_id":"exec_thread_1","message":"Codex is running"}
{"type":"turn.completed","thread_id":"exec_thread_1","message":"Tests passed"}
"""
let execEvents = CodexRealtimeEventParser.execEvents(
    fromJSONL: execJSONL,
    defaultThreadID: "exec-default",
    title: "Junimo Codex",
    now: Date(timeIntervalSince1970: 1_800_000_200)
)
expect(execEvents.contains(where: { event in
    if case let .thread(thread) = event {
        return thread.id == "exec:exec_thread_1" && thread.status == .running
    }
    return false
}), "Exec parser should emit running thread update")
expect(execEvents.contains(where: { event in
    if case let .thread(thread) = event {
        return thread.id == "exec:exec_thread_1" && thread.status == .completed && thread.detail == "Tests passed"
    }
    return false
}), "Exec parser should emit completed thread update")

let execFailureEvents = CodexRealtimeEventParser.execEvents(
    fromJSONL: #"{"type":"turn.failed","thread_id":"exec_thread_2","message":"Build failed"}"#,
    defaultThreadID: "exec-default",
    title: "Junimo Codex",
    now: Date(timeIntervalSince1970: 1_800_000_300)
)
expect(execFailureEvents.contains(where: { event in
    if case let .thread(thread) = event {
        return thread.id == "exec:exec_thread_2" && thread.status == .failed && thread.detail == "Build failed"
    }
    return false
}), "Exec parser should emit failed thread update")

let realtimeCoordinator = TaskCoordinator(now: codexStart)
for event in realtimeEvents {
    realtimeCoordinator.applyCodexRealtimeEvent(event, now: codexStart)
}
expect(realtimeCoordinator.codexMonitor.usage.summaryText == "36% left", "Coordinator should apply realtime usage events")
expect(realtimeCoordinator.codexMonitor.threads.first?.id == "local:thread_realtime_1", "Coordinator should apply realtime thread events")
realtimeCoordinator.applyCodexRealtimeEvent(
    .thread(
        CodexThreadSummary(
            id: "local:thread_realtime_1",
            title: "Realtime fix",
            status: .completed,
            detail: "Done from realtime stream",
            updatedAt: codexStart.addingTimeInterval(20)
        )
    ),
    now: codexStart.addingTimeInterval(20)
)
expect(realtimeCoordinator.pendingNotifications.first?.title == "Codex thread complete", "Realtime terminal transition should request notification")

let hoverStart = Date(timeIntervalSince1970: 200)
let hoverCoordinator = TaskCoordinator(now: hoverStart)
hoverCoordinator.pointerEntered()
expect(hoverCoordinator.isExpanded, "Console should expand on hover")
hoverCoordinator.pointerExited(at: hoverStart)
expect(!hoverCoordinator.isExpanded, "Console should collapse immediately after hover exit")

let cornerCoordinator = TaskCoordinator(now: Date(timeIntervalSince1970: 210))
var cornerFeature = CornerNoteFeature(core: SwiftFallbackCore())
expect(!cornerFeature.snapshot.isExpanded, "CornerNoteFeature should start collapsed")
cornerFeature.setExpanded(true)
cornerFeature.updateText("Feature note")
cornerFeature.addTodo(title: "Feature todo")
let featureTodo = cornerFeature.snapshot.todos.last
// 业务语义：CornerNoteFeature 是角落便签的 Swift 状态 owner，内容变更后公开 snapshot 必须与 core 结果一致。
expect(cornerFeature.snapshot.isExpanded, "CornerNoteFeature should expand")
expect(cornerFeature.snapshot.text == "Feature note", "CornerNoteFeature should update text from core snapshot")
expect(featureTodo?.title == "Feature todo", "CornerNoteFeature should append todo from core snapshot")
if let featureTodoID = featureTodo?.id {
    cornerFeature.updateTodo(id: featureTodoID, title: "Feature todo done")
    cornerFeature.toggleTodo(id: featureTodoID)
    expect(cornerFeature.snapshot.todos.last?.title == "Feature todo done", "CornerNoteFeature should update todo title")
    expect(cornerFeature.snapshot.todos.last?.isDone == true, "CornerNoteFeature should toggle todo done state")
}
cornerFeature.setExpanded(false)
expect(!cornerFeature.snapshot.isExpanded, "CornerNoteFeature should collapse")
expect(cornerFeature.snapshot.text == "Feature note", "CornerNoteFeature collapse should not clear text")

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
let pomodoroFeatureCore = FakePomodoroCore()
var pomodoroFeature = PomodoroFeature(core: pomodoroFeatureCore)
pomodoroFeature.start(duration: 60, now: pomodoroStart)
// 业务语义：PomodoroFeature 暴露 core timer 的 active projection，不让 coordinator 拥有第二份 timer 状态。
expect(pomodoroFeature.activePomodoro != nil, "PomodoroFeature should expose active timer projection")
let earlyPomodoroEffects = pomodoroFeature.advanceTime(to: pomodoroStart.addingTimeInterval(30))
expect(earlyPomodoroEffects.notifications.isEmpty, "PomodoroFeature should not emit notification before timer completes")
expect(pomodoroFeature.activePomodoro != nil, "PomodoroFeature should keep active projection before completion")
let completedPomodoroEffects = pomodoroFeature.advanceTime(to: pomodoroStart.addingTimeInterval(60))
expect(pomodoroFeature.activePomodoro == nil, "PomodoroFeature should clear active projection after completion")
expect(completedPomodoroEffects.notifications.first?.title == "Pomodoro complete", "PomodoroFeature should emit completion notification effect")

var notificationOutbox = NotificationOutbox()
let firstNotification = NotificationRequest(
    id: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
    title: "First",
    body: "First body",
    createdAt: pomodoroStart
)
let secondNotification = NotificationRequest(
    id: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!,
    title: "Second",
    body: "Second body",
    createdAt: pomodoroStart.addingTimeInterval(1)
)
// 业务语义：NotificationOutbox 是系统通知请求队列的唯一 owner，按入队顺序暴露待投递请求。
notificationOutbox.enqueue(firstNotification)
notificationOutbox.enqueue(contentsOf: [secondNotification])
expect(notificationOutbox.pending.map(\.id) == [firstNotification.id, secondNotification.id], "NotificationOutbox should preserve enqueue order")
notificationOutbox.markDelivered(id: firstNotification.id)
expect(notificationOutbox.pending.map(\.id) == [secondNotification.id], "NotificationOutbox should remove only the delivered request")
notificationOutbox.markDelivered(id: UUID(uuidString: "00000000-0000-4000-8000-000000000199")!)
expect(notificationOutbox.pending.map(\.id) == [secondNotification.id], "NotificationOutbox should ignore unknown delivered IDs")

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
