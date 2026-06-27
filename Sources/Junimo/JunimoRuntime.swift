import Foundation
import JunimoCore

final class JunimoRuntime {
    let coordinator: TaskCoordinator

    private let reminderAdapter: ReminderDelivering
    private let codexProvider: CodexMonitorSnapshotProviding
    private let codexRealtimeStream: CodexRealtimeEventStreaming?
    private let codexMonitorInterval: TimeInterval
    private let codexMonitorEnabled: Bool
    private let healthReporter: LaunchHealthReporter
    private let releaseChecker: ReleaseChecking
    private let updateInstaller: ExternalUpdateInstalling
    private let softwareUpdateChecksOnStart: Bool
    private let installDirectoryProvider: () -> String
    private var reminderBridge: ReminderDeliveryBridge?
    private var codexMonitorBridge: CodexMonitorRefreshBridge?
    private var softwareUpdateService: SoftwareUpdateService?

    /// 业务语义：runtime 接收 app 层依赖，保证产品 wiring 有单一组合入口。
    init(
        coordinator: TaskCoordinator = TaskCoordinator(),
        reminderAdapter: ReminderDelivering = UserNotificationReminderAdapter(),
        codexProvider: CodexMonitorSnapshotProviding = CodexCLIStatusProvider(),
        codexRealtimeStream: CodexRealtimeEventStreaming? = ProcessCodexAppServerEventStream(),
        codexMonitorInterval: TimeInterval = 120,
        codexMonitorEnabled: Bool = true,
        releaseChecker: ReleaseChecking = GitHubReleaseChecker(),
        updateInstaller: ExternalUpdateInstalling = ExternalUpdateInstaller(),
        softwareUpdateChecksOnStart: Bool = true,
        installDirectoryProvider: @escaping () -> String = {
            Bundle.main.bundleURL.deletingLastPathComponent().path
        },
        healthReporter: LaunchHealthReporter = LaunchHealthReporter()
    ) {
        self.coordinator = coordinator
        self.reminderAdapter = reminderAdapter
        self.codexProvider = codexProvider
        self.codexRealtimeStream = codexRealtimeStream
        self.codexMonitorInterval = codexMonitorInterval
        self.codexMonitorEnabled = codexMonitorEnabled
        self.releaseChecker = releaseChecker
        self.updateInstaller = updateInstaller
        self.softwareUpdateChecksOnStart = softwareUpdateChecksOnStart
        self.installDirectoryProvider = installDirectoryProvider
        self.healthReporter = healthReporter
    }

    /// 业务语义：启动 app runtime 时统一拉起平台 bridge，避免 AppDelegate 直接组装产品依赖。
    func start(onCodexMonitorUpdated: (() -> Void)? = nil) {
        reminderBridge = ReminderDeliveryBridge(coordinator: coordinator, adapter: reminderAdapter)
        let updateService = SoftwareUpdateService(
            coordinator: coordinator,
            checker: releaseChecker,
            checksOnStart: softwareUpdateChecksOnStart
        )
        softwareUpdateService = updateService
        updateService.start()
        guard codexMonitorEnabled else {
            return
        }

        let bridge = CodexMonitorRefreshBridge(
            coordinator: coordinator,
            provider: codexProvider,
            realtimeStream: codexRealtimeStream,
            interval: codexMonitorInterval,
            onMonitorUpdated: onCodexMonitorUpdated
        )
        codexMonitorBridge = bridge
        bridge.start()
    }

    /// 业务语义：停止 app runtime 时集中释放后台 monitor 生命周期。
    func stop() {
        codexMonitorBridge?.stop()
        codexMonitorBridge = nil
        softwareUpdateService?.stop()
        softwareUpdateService = nil
        reminderBridge = nil
    }

    /// 业务语义：菜单手动检查只委托 runtime/service，不让 AppDelegate 解析 release 元数据。
    func checkForUpdatesNow() {
        softwareUpdateService?.checkNow(reason: .manual)
    }

    /// 业务语义：用户点击更新按钮后才启动外部 updater，并且只能更新当前 app 所在目录。
    func installAvailableUpdate() {
        coordinator.startSelfUpdateInstall()
        guard coordinator.selfUpdateSnapshot.state == .installing else { return }
        do {
            try updateInstaller.installLatest(from: installDirectoryProvider())
        } catch {
            coordinator.failSelfUpdateInstall(message: error.localizedDescription)
        }
    }

    /// 业务语义：functional health scenario 通过 runtime 进入产品状态，保持 AppDelegate 只负责展示面。
    func runLaunchHealthScenario() {
        coordinator.pointerEntered()
        coordinator.updateCommandQuery("focus")
        coordinator.performCommand(id: "codex")
        coordinator.performCommand(id: "pomodoro-10s")
        coordinator.setDensity(.compact)
        coordinator.setCornerNoteExpanded(true)
        coordinator.updateCornerNoteText("Health scenario note")
        coordinator.addCornerTodo(title: "Verify corner note")
    }

    /// 业务语义：健康快照由 runtime 组合 coordinator state 和 app shell panel diagnostics。
    func writeHealth(panel: PanelDiagnostics) {
        healthReporter.write(coordinator: coordinator, panel: panel)
    }
}
