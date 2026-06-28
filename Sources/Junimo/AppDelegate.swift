import AppKit
import Combine
import JunimoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: JunimoRuntime?
    private var lifecycleWindow: NSWindow?
    private var panelController: NotchPanelController?
    private var cornerNotePanelController: CornerNotePanelController?
    private var statusItem: NSStatusItem?
    private var statusMenuUpdateItem: NSMenuItem?
    private var coordinatorCancellable: AnyCancellable?
    private var lifecycleDiagnosticsTimers: [Timer] = []
    private var allowsTermination = false

    /// 业务语义：生命周期锚点尽早进入 AppKit 启动阶段，先于业务 runtime 和 panel 组装。
    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchLifecycleDiagnostics.record("application-will-finish-launching")
        installLifecycleAnchorWindow()
    }

    /// 业务语义：AppDelegate 只组装 AppKit surface，把产品 runtime wiring 交给 JunimoRuntime。
    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLifecycleDiagnostics.record("application-did-finish-launching")
        NSApp.setActivationPolicy(.accessory)

        let runtime = JunimoRuntime(
            codexMonitorEnabled: ProcessInfo.processInfo.environment["JUNIMO_DISABLE_CODEX_MONITOR"] != "1"
        )
        self.runtime = runtime
        let coordinator = runtime.coordinator
        let controller = NotchPanelController(coordinator: coordinator)
        panelController = controller
        controller.show()
        LaunchLifecycleDiagnostics.record("notch-panel-shown", fields: [
            "visible": "\(controller.diagnostics().isVisible)",
            "floating": "\(controller.diagnostics().isFloatingPanel)"
        ])
        let cornerController = CornerNotePanelController(coordinator: coordinator)
        cornerNotePanelController = cornerController
        cornerController.show()
        LaunchLifecycleDiagnostics.record("corner-panel-shown")
        installStatusItem()
        LaunchLifecycleDiagnostics.record("status-item-installed")
        recordWindowSnapshot(label: "after-status-item")
        scheduleLifecycleDiagnostics()
        coordinatorCancellable = coordinator.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshStatusMenu()
            }
        }
        runtime.start { [weak runtime, weak controller] in
            guard let runtime, let controller else { return }
            runtime.writeHealth(panel: controller.diagnostics())
            LaunchLifecycleDiagnostics.record("health-written-from-monitor-callback")
        }
        DispatchQueue.main.async { [weak runtime] in
            guard let runtime else { return }
            if ProcessInfo.processInfo.environment["JUNIMO_HEALTH_SCENARIO"] == "1" {
                runtime.runLaunchHealthScenario()
                controller.show()
                cornerController.show()
            }
            runtime.writeHealth(panel: controller.diagnostics())
            LaunchLifecycleDiagnostics.record("health-written-from-launch")
        }
    }

    /// 业务语义：Junimo 是菜单栏辅助工具，关闭窗口不等于退出应用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        LaunchLifecycleDiagnostics.record("application-should-terminate-after-last-window-closed")
        return false
    }

    /// 业务语义：只有用户主动退出或更新安装才能结束常驻进程，AppKit automatic termination 不能回收菜单栏工具。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        LaunchLifecycleDiagnostics.record("application-should-terminate", fields: [
            "allowed": "\(allowsTermination)"
        ])
        return allowsTermination ? .terminateNow : .terminateCancel
    }

    /// 业务语义：应用退出时通过 runtime 停止后台 monitor，避免 AppKit 层散落清理逻辑。
    func applicationWillTerminate(_ notification: Notification) {
        LaunchLifecycleDiagnostics.record("application-will-terminate")
        recordWindowSnapshot(label: "will-terminate")
        lifecycleDiagnosticsTimers.forEach { $0.invalidate() }
        lifecycleDiagnosticsTimers = []
        runtime?.stop()
        lifecycleWindow?.close()
        lifecycleWindow = nil
    }

    /// 业务语义：状态栏 Show 命令只恢复 app shell 面板，不触碰产品 runtime wiring。
    @objc private func showPanelFromMenu() {
        panelController?.expandAndShow()
    }

    /// 业务语义：状态栏 Quit 命令保持 macOS app shell 的退出入口。
    @objc private func quitFromMenu() {
        allowsTermination = true
        LaunchLifecycleDiagnostics.record("quit-requested-from-menu")
        NSApp.terminate(nil)
    }

    /// 业务语义：状态栏更新入口只表达用户意图，检查和安装决策交给 runtime / core 状态。
    @objc private func updateFromMenu() {
        guard let runtime else { return }
        if runtime.coordinator.selfUpdateSnapshot.state == .updateAvailable {
            runtime.installAvailableUpdate()
            allowsTermination = true
            LaunchLifecycleDiagnostics.record("terminate-requested-for-update")
            NSApp.terminate(nil)
        } else {
            runtime.checkForUpdatesNow()
        }
        refreshStatusMenu()
    }

    /// 业务语义：状态栏菜单属于 AppKit surface，不进入产品 runtime。
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Junimo")
        item.button?.contentTintColor = .systemGreen

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Junimo", action: #selector(showPanelFromMenu), keyEquivalent: ""))
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(updateFromMenu), keyEquivalent: "")
        statusMenuUpdateItem = updateItem
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Junimo", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        refreshStatusMenu()
    }

    /// 业务语义：LSUIElement 菜单栏应用也需要一个 AppKit 生命周期锚点，避免无普通窗口时被 automatic termination 回收。
    private func installLifecycleAnchorWindow() {
        guard lifecycleWindow == nil else { return }
        let frame = lifecycleAnchorFrame()
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.02
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.title = "Junimo Lifecycle"
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()
        lifecycleWindow = window
        LaunchLifecycleDiagnostics.record("lifecycle-window-installed", fields: [
            "visible": "\(window.isVisible)",
            "alpha": "\(window.alphaValue)",
            "frame": "\(Int(window.frame.origin.x)),\(Int(window.frame.origin.y)),\(Int(window.frame.width)),\(Int(window.frame.height))",
            "styleMask": "\(window.styleMask.rawValue)"
        ])
    }

    /// 业务语义：生命周期锚点必须位于屏幕内且非透明，否则 AppKit 可能仍判断为没有 open window。
    private func lifecycleAnchorFrame() -> NSRect {
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 10, height: 10)
        return NSRect(x: screenFrame.minX + 1, y: screenFrame.minY + 1, width: 2, height: 2)
    }

    /// 业务语义：启动后定点记录窗口和保活状态，用于定位 AppKit 为何仍认为没有窗口可防止 automatic termination。
    private func scheduleLifecycleDiagnostics() {
        lifecycleDiagnosticsTimers.forEach { $0.invalidate() }
        lifecycleDiagnosticsTimers = [1, 3, 6, 9, 12].map { seconds in
            Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                self?.recordWindowSnapshot(label: "startup-\(seconds)s")
            }
        }
    }

    /// 业务语义：窗口快照是启动诊断的核心证据，记录 AppKit 当前认可的 window 列表，而不是只记录业务 panel 状态。
    private func recordWindowSnapshot(label: String) {
        let windows = NSApp.windows.enumerated().map { index, window in
            let frame = window.frame
            return [
                "#\(index)",
                "title=\(window.title.replacingOccurrences(of: " ", with: "_"))",
                "visible=\(window.isVisible)",
                "miniaturized=\(window.isMiniaturized)",
                "alpha=\(String(format: "%.3f", window.alphaValue))",
                "level=\(Int(window.level.rawValue))",
                "style=\(window.styleMask.rawValue)",
                "frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))"
            ].joined(separator: ",")
        }.joined(separator: "|")
        LaunchLifecycleDiagnostics.record("window-snapshot", fields: [
            "label": label,
            "activationPolicy": "\(NSApp.activationPolicy().rawValue)",
            "activity": AppLifecycleRetainer.hasActivityToken ? "held" : "missing",
            "hidden": "\(NSApp.isHidden)",
            "windows": windows.isEmpty ? "none" : windows
        ])
    }

    /// 业务语义：菜单标题是 self-update 快照的派生投影，不在 AppDelegate 内重新判断版本。
    private func refreshStatusMenu() {
        guard let item = statusMenuUpdateItem, let runtime else { return }
        switch runtime.coordinator.selfUpdateSnapshot.state {
        case .idle:
            item.title = "Check for Updates..."
            item.isEnabled = true
        case .checking:
            item.title = "Checking for Updates..."
            item.isEnabled = false
        case .upToDate:
            item.title = "Junimo is Up to Date"
            item.isEnabled = true
        case .updateAvailable:
            item.title = "Install Update..."
            item.isEnabled = true
        case .checkFailed:
            item.title = "Check Failed - Try Again"
            item.isEnabled = true
        case .installing:
            item.title = "Installing Update..."
            item.isEnabled = false
        case .installFailed:
            item.title = "Install Failed - Try Again"
            item.isEnabled = true
        }
    }
}
