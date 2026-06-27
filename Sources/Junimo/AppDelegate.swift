import AppKit
import JunimoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: JunimoRuntime?
    private var panelController: NotchPanelController?
    private var cornerNotePanelController: CornerNotePanelController?
    private var statusItem: NSStatusItem?

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

    /// 业务语义：状态栏菜单属于 AppKit surface，不进入产品 runtime。
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Junimo")
        item.button?.contentTintColor = .systemGreen

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Junimo", action: #selector(showPanelFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Junimo", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }
}
