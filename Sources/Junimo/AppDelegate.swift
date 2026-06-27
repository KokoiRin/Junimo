import AppKit
import Combine
import JunimoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: JunimoRuntime?
    private var panelController: NotchPanelController?
    private var cornerNotePanelController: CornerNotePanelController?
    private var statusItem: NSStatusItem?
    private var statusMenuUpdateItem: NSMenuItem?
    private var coordinatorCancellable: AnyCancellable?

    /// 业务语义：AppDelegate 只组装 AppKit surface，把产品 runtime wiring 交给 JunimoRuntime。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runtime = JunimoRuntime(
            codexMonitorEnabled: ProcessInfo.processInfo.environment["JUNIMO_DISABLE_CODEX_MONITOR"] != "1"
        )
        self.runtime = runtime
        let coordinator = runtime.coordinator
        let controller = NotchPanelController(coordinator: coordinator)
        panelController = controller
        controller.show()
        let cornerController = CornerNotePanelController(coordinator: coordinator)
        cornerNotePanelController = cornerController
        cornerController.show()
        installStatusItem()
        coordinatorCancellable = coordinator.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshStatusMenu()
            }
        }
        runtime.start { [weak runtime, weak controller] in
            guard let runtime, let controller else { return }
            runtime.writeHealth(panel: controller.diagnostics())
        }
        DispatchQueue.main.async { [weak runtime] in
            guard let runtime else { return }
            if ProcessInfo.processInfo.environment["JUNIMO_HEALTH_SCENARIO"] == "1" {
                runtime.runLaunchHealthScenario()
                controller.show()
                cornerController.show()
            }
            runtime.writeHealth(panel: controller.diagnostics())
        }
    }

    /// 业务语义：Junimo 是菜单栏辅助工具，关闭窗口不等于退出应用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 业务语义：应用退出时通过 runtime 停止后台 monitor，避免 AppKit 层散落清理逻辑。
    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }

    /// 业务语义：状态栏 Show 命令只恢复 app shell 面板，不触碰产品 runtime wiring。
    @objc private func showPanelFromMenu() {
        panelController?.expandAndShow()
    }

    /// 业务语义：状态栏 Quit 命令保持 macOS app shell 的退出入口。
    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    /// 业务语义：状态栏更新入口只表达用户意图，检查和安装决策交给 runtime / core 状态。
    @objc private func updateFromMenu() {
        guard let runtime else { return }
        if runtime.coordinator.selfUpdateSnapshot.state == .updateAvailable {
            runtime.installAvailableUpdate()
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
