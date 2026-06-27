import Combine
import Foundation
import JunimoCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

final class FakeSnapshotProvider: CodexMonitorSnapshotProviding {
    private let snapshot: CodexMonitorSnapshot
    private(set) var loadCount = 0

    init(snapshot: CodexMonitorSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot(now: Date) -> CodexMonitorSnapshot {
        loadCount += 1
        return snapshot
    }
}

final class FailingRealtimeStream: CodexRealtimeEventStreaming {
    private(set) var started = false
    private(set) var stopped = false

    func start(
        onEvent: @escaping (CodexRealtimeEvent) -> Void,
        onFinished: @escaping (CodexIntegrationFinding?) -> Void
    ) {
        started = true
        onFinished(
            CodexIntegrationFinding(
                id: "app-server-realtime",
                title: "Realtime Codex events",
                status: .degraded,
                detail: "Fake stream unavailable."
            )
        )
    }

    func stop() {
        stopped = true
    }
}

final class MonitorUpdateRecorder {
    private(set) var count = 0

    /// 业务语义：记录 runtime/monitor 公开更新回调，测试不绑定内部 timer 实现。
    func record() {
        count += 1
    }
}

final class RecordingReminderAdapter: ReminderDelivering {
    private(set) var delivered: [NotificationRequest] = []

    /// 业务语义：用 fake 捕获系统通知副作用，避免 app smoke 触发真实通知权限。
    func deliver(_ request: NotificationRequest) {
        delivered.append(request)
    }
}

final class FakeReleaseChecker: ReleaseChecking {
    var result: SelfUpdateCheckResult
    private(set) var checkCount = 0
    var delayCompletion = false
    var completesOnBackgroundQueue = false
    private var pendingCompletion: ((SelfUpdateCheckResult) -> Void)?

    init(result: SelfUpdateCheckResult) {
        self.result = result
    }

    /// 业务语义：fake checker 让测试控制 release 检查成功、失败和延迟回调。
    func checkLatestRelease(completion: @escaping (SelfUpdateCheckResult) -> Void) {
        checkCount += 1
        if delayCompletion {
            pendingCompletion = completion
        } else if completesOnBackgroundQueue {
            let result = result
            DispatchQueue.global(qos: .utility).async {
                completion(result)
            }
        } else {
            completion(result)
        }
    }

    /// 业务语义：延迟完成用于验证 service stop 后不会继续污染 coordinator 状态。
    func completePending() {
        pendingCompletion?(result)
        pendingCompletion = nil
    }
}

final class RecordingUpdateInstaller: ExternalUpdateInstalling {
    private(set) var installDirectories: [String] = []

    /// 业务语义：fake installer 只记录用户确认后的安装意图，不触发真实文件替换。
    func installLatest(from installDirectory: String) throws {
        installDirectories.append(installDirectory)
    }
}

final class FakeMonitorSink: CodexMonitorEventSink {
    private(set) var snapshots: [CodexMonitorSnapshot] = []
    private(set) var events: [CodexRealtimeEvent] = []
    private(set) var findings: [CodexIntegrationFinding] = []

    func refreshCodexMonitor(_ snapshot: CodexMonitorSnapshot) {
        snapshots.append(snapshot)
    }

    func applyCodexRealtimeEvent(_ event: CodexRealtimeEvent) {
        events.append(event)
    }

    func applyCodexIntegrationFinding(_ finding: CodexIntegrationFinding) {
        findings.append(finding)
    }
}

func waitUntil(_ deadline: Date, _ condition: @escaping () -> Bool) {
    while Date() < deadline {
        if condition() {
            return
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

let now = Date(timeIntervalSince1970: 1_800_000_500)
let snapshot = CodexMonitorSnapshot(
    usage: CodexUsageSnapshot(
        status: .available,
        planLabel: "Plus",
        detail: "Loaded from fake snapshot provider",
        source: "fake-provider",
        primaryWindow: CodexUsageWindow(label: "5h", usedPercent: 12)
    ),
    threads: [
        CodexThreadSummary(
            id: "cloud:fake-task",
            title: "Fake cloud task",
            status: .running,
            detail: "Snapshot fallback still works",
            updatedAt: now
        )
    ],
    findings: [],
    refreshedAt: now
)
let monitorSink = FakeMonitorSink()
let monitorProvider = FakeSnapshotProvider(snapshot: snapshot)
let monitorStream = FailingRealtimeStream()
let monitorRecorder = MonitorUpdateRecorder()
let monitorService = CodexMonitorService(
    sink: monitorSink,
    provider: monitorProvider,
    realtimeStream: monitorStream,
    interval: 60,
    onMonitorUpdated: monitorRecorder.record
)
monitorService.start()
waitUntil(Date().addingTimeInterval(2)) {
    monitorSink.snapshots.first?.usage.source == "fake-provider"
        && monitorSink.findings.contains { $0.id == "app-server-realtime" }
}
monitorService.stop()

expect(monitorProvider.loadCount == 1, "Monitor service should request an immediate snapshot refresh")
expect(monitorRecorder.count >= 1, "Monitor service should report typed sink updates")
expect(monitorStream.started, "Monitor service should start realtime stream")
expect(monitorStream.stopped, "Monitor service should stop realtime stream")
expect(monitorSink.snapshots.first?.threads.first?.id == "cloud:fake-task", "Monitor service should deliver snapshot through typed sink")
expect(
    monitorSink.findings.contains { $0.id == "app-server-realtime" && $0.status == .degraded },
    "Monitor service should deliver realtime findings through typed sink"
)

let updateCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let updateChecker = FakeReleaseChecker(
    result: .success(ReleaseInfo(version: ReleaseVersion("0.1.5")!, assetName: "Junimo-macos-arm64.zip"))
)
let updateService = SoftwareUpdateService(coordinator: updateCoordinator, checker: updateChecker, checksOnStart: false, nowProvider: { now })
updateService.start()
updateService.checkNow(reason: .manual)
waitUntil(Date().addingTimeInterval(2)) {
    updateCoordinator.selfUpdateSnapshot.state == .updateAvailable
}
expect(updateChecker.checkCount == 1, "Manual update check should call release checker")
expect(updateCoordinator.selfUpdateSnapshot.state == .updateAvailable, "Manual update check should expose available update")
updateService.stop()

let failedUpdateCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let failedChecker = FakeReleaseChecker(result: .failure("release metadata unavailable"))
let failedService = SoftwareUpdateService(coordinator: failedUpdateCoordinator, checker: failedChecker, checksOnStart: false, nowProvider: { now })
failedService.start()
failedService.checkNow(reason: .manual)
waitUntil(Date().addingTimeInterval(2)) {
    failedUpdateCoordinator.selfUpdateSnapshot.state == .checkFailed
}
expect(failedUpdateCoordinator.selfUpdateSnapshot.state == .checkFailed, "Failed update check should update visible state")
expect(failedUpdateCoordinator.selfUpdateSnapshot.message == "release metadata unavailable", "Failed update check should preserve failure message")
failedService.stop()

let backgroundUpdateCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let backgroundChecker = FakeReleaseChecker(
    result: .success(ReleaseInfo(version: ReleaseVersion("0.1.5")!, assetName: "Junimo-macos-arm64.zip"))
)
backgroundChecker.completesOnBackgroundQueue = true
var backgroundUpdatePublishedOffMain = false
let backgroundUpdateCancellable = backgroundUpdateCoordinator.objectWillChange.sink {
    if !Thread.isMainThread {
        backgroundUpdatePublishedOffMain = true
    }
}
let backgroundUpdateService = SoftwareUpdateService(coordinator: backgroundUpdateCoordinator, checker: backgroundChecker, checksOnStart: false, nowProvider: { now })
backgroundUpdateService.start()
backgroundUpdateService.checkNow(reason: .manual)
waitUntil(Date().addingTimeInterval(2)) {
    backgroundUpdateCoordinator.selfUpdateSnapshot.state == .updateAvailable
}
backgroundUpdateService.stop()
expect(!backgroundUpdatePublishedOffMain, "Background release checks must publish coordinator changes on the main thread")
_ = backgroundUpdateCancellable

let stoppedUpdateCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let delayedChecker = FakeReleaseChecker(
    result: .success(ReleaseInfo(version: ReleaseVersion("0.1.5")!, assetName: "Junimo-macos-arm64.zip"))
)
delayedChecker.delayCompletion = true
let stoppedService = SoftwareUpdateService(coordinator: stoppedUpdateCoordinator, checker: delayedChecker, checksOnStart: false, nowProvider: { now })
stoppedService.start()
stoppedService.checkNow(reason: .manual)
stoppedService.stop()
delayedChecker.completePending()
expect(stoppedUpdateCoordinator.selfUpdateSnapshot.state == .checking, "Stopped update service should not apply delayed checker results")

let coordinator = TaskCoordinator(now: now)
let provider = FakeSnapshotProvider(snapshot: snapshot)
let stream = FailingRealtimeStream()
let recorder = MonitorUpdateRecorder()
let bridge = CodexMonitorRefreshBridge(
    coordinator: coordinator,
    provider: provider,
    realtimeStream: stream,
    interval: 60,
    onMonitorUpdated: recorder.record
)

bridge.start()
waitUntil(Date().addingTimeInterval(2)) {
    coordinator.codexMonitor.usage.source == "fake-provider"
        && coordinator.codexMonitor.findings.contains { $0.id == "app-server-realtime" }
}
bridge.stop()

expect(provider.loadCount == 1, "Bridge should request an immediate snapshot refresh")
expect(recorder.count >= 1, "Bridge should report monitor updates after refresh or realtime findings")
expect(stream.started, "Bridge should start the realtime stream")
expect(stream.stopped, "Bridge should stop the realtime stream")
expect(coordinator.codexMonitor.usage.source == "fake-provider", "Snapshot fallback should update monitor usage")
expect(coordinator.codexMonitor.threads.first?.id == "cloud:fake-task", "Snapshot fallback should update monitor threads")
expect(
    coordinator.codexMonitor.findings.contains { $0.id == "app-server-realtime" && $0.status == .degraded },
    "Realtime stream failure should be exposed as a degraded finding"
)

let backgroundCodexCoordinator = TaskCoordinator(now: now)
var backgroundCodexPublishedOffMain = false
let backgroundCodexCancellable = backgroundCodexCoordinator.objectWillChange.sink {
    if !Thread.isMainThread {
        backgroundCodexPublishedOffMain = true
    }
}
DispatchQueue.global(qos: .utility).async {
    backgroundCodexCoordinator.refreshCodexMonitor(snapshot)
}
waitUntil(Date().addingTimeInterval(2)) {
    backgroundCodexCoordinator.codexMonitor.usage.source == "fake-provider"
}
expect(!backgroundCodexPublishedOffMain, "Background Codex refreshes must publish coordinator changes on the main thread")
_ = backgroundCodexCancellable

let runtimeCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let runtimeProvider = FakeSnapshotProvider(snapshot: snapshot)
let runtimeStream = FailingRealtimeStream()
let runtimeRecorder = MonitorUpdateRecorder()
let runtimeReminderAdapter = RecordingReminderAdapter()
let runtimeReleaseChecker = FakeReleaseChecker(
    result: .success(ReleaseInfo(version: ReleaseVersion("0.1.5")!, assetName: "Junimo-macos-arm64.zip"))
)
let runtimeInstaller = RecordingUpdateInstaller()
let runtime = JunimoRuntime(
    coordinator: runtimeCoordinator,
    reminderAdapter: runtimeReminderAdapter,
    codexProvider: runtimeProvider,
    codexRealtimeStream: runtimeStream,
    codexMonitorInterval: 60,
    releaseChecker: runtimeReleaseChecker,
    updateInstaller: runtimeInstaller,
    softwareUpdateChecksOnStart: true,
    installDirectoryProvider: { "/Applications" }
)

runtime.start(onCodexMonitorUpdated: runtimeRecorder.record)
waitUntil(Date().addingTimeInterval(2)) {
    runtime.coordinator.codexMonitor.usage.source == "fake-provider"
        && runtime.coordinator.codexMonitor.findings.contains { $0.id == "app-server-realtime" }
        && runtime.coordinator.selfUpdateSnapshot.state == .updateAvailable
}
runtime.installAvailableUpdate()
runtime.coordinator.startPomodoro(duration: 1, now: now)
runtime.coordinator.advanceTime(to: now.addingTimeInterval(1))
waitUntil(Date().addingTimeInterval(2)) {
    runtimeReminderAdapter.delivered.contains { $0.title == "Pomodoro complete" }
        && runtime.coordinator.pendingNotifications.isEmpty
}
runtime.runLaunchHealthScenario()
runtime.stop()

expect(runtime.coordinator === runtimeCoordinator, "Runtime should expose its coordinator for app surfaces")
expect(runtimeProvider.loadCount == 1, "Runtime should request an immediate Codex snapshot refresh")
expect(runtimeRecorder.count >= 1, "Runtime should report Codex monitor updates")
expect(runtimeStream.started, "Runtime should start realtime Codex stream")
expect(runtimeStream.stopped, "Runtime should stop realtime Codex stream")
expect(runtimeReleaseChecker.checkCount == 1, "Runtime should start one launch-time update check")
expect(runtimeInstaller.installDirectories == ["/Applications"], "Runtime should install available update in current install directory")
let realtimeFindingDelivered = runtime.coordinator.codexMonitor.findings.contains {
    $0.id == "app-server-realtime" && $0.status == CodexCapabilityStatus.degraded
}
expect(realtimeFindingDelivered, "Runtime should expose realtime findings through coordinator state")
expect(
    runtimeReminderAdapter.delivered.contains { $0.title == "Pomodoro complete" },
    "Runtime should deliver notifications through the existing pending notification projection"
)
expect(runtime.coordinator.pendingNotifications.isEmpty, "Runtime reminder delivery should acknowledge delivered notifications")
expect(runtime.coordinator.preferences.density == ConsoleDensity.compact, "Runtime health scenario should exercise compact density")
expect(runtime.coordinator.isCornerNoteExpanded, "Runtime health scenario should exercise Corner Note expansion")
expect(runtime.coordinator.cornerNoteText == "Health scenario note", "Runtime health scenario should write Corner Note text")

let stoppedRuntimeCoordinator = TaskCoordinator(currentVersion: ReleaseVersion("0.1.4")!, now: now)
let stoppedRuntimeChecker = FakeReleaseChecker(
    result: .success(ReleaseInfo(version: ReleaseVersion("0.1.5")!, assetName: "Junimo-macos-arm64.zip"))
)
stoppedRuntimeChecker.delayCompletion = true
let stoppedRuntime = JunimoRuntime(
    coordinator: stoppedRuntimeCoordinator,
    reminderAdapter: RecordingReminderAdapter(),
    codexMonitorEnabled: false,
    releaseChecker: stoppedRuntimeChecker,
    softwareUpdateChecksOnStart: true
)
stoppedRuntime.start()
stoppedRuntime.stop()
stoppedRuntimeChecker.completePending()
expect(stoppedRuntime.coordinator.selfUpdateSnapshot.state == .checking, "Runtime stop should prevent delayed update check mutation")

print("Junimo app bridge smoke tests passed")
