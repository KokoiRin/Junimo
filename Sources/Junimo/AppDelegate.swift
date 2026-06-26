import AppKit
import JunimoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = TaskCoordinator()
    private var panelController: NotchPanelController?
    private var cornerNotePanelController: CornerNotePanelController?
    private var reminderBridge: ReminderDeliveryBridge?
    private var codexMonitorBridge: CodexMonitorRefreshBridge?
    private var statusItem: NSStatusItem?
    private let healthReporter = LaunchHealthReporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        reminderBridge = ReminderDeliveryBridge(
            coordinator: coordinator,
            adapter: UserNotificationReminderAdapter()
        )
        if ProcessInfo.processInfo.environment["JUNIMO_DISABLE_CODEX_MONITOR"] != "1" {
            let bridge = CodexMonitorRefreshBridge(coordinator: coordinator)
            codexMonitorBridge = bridge
            bridge.start()
        }

        let controller = NotchPanelController(coordinator: coordinator)
        panelController = controller
        controller.show()
        let cornerController = CornerNotePanelController(coordinator: coordinator)
        cornerNotePanelController = cornerController
        cornerController.show()
        installStatusItem()
        DispatchQueue.main.async { [coordinator, healthReporter] in
            if ProcessInfo.processInfo.environment["JUNIMO_HEALTH_SCENARIO"] == "1" {
                coordinator.pointerEntered()
                coordinator.updateCommandQuery("focus")
                coordinator.performCommand(id: "codex")
                coordinator.performCommand(id: "pomodoro-10s")
                coordinator.setDensity(.compact)
                coordinator.setCornerNoteExpanded(true)
                coordinator.updateCornerNoteText("Health scenario note")
                coordinator.addCornerTodo(title: "Verify corner note")
                controller.show()
                cornerController.show()
            }
            healthReporter.write(coordinator: coordinator, panel: controller.diagnostics())
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        codexMonitorBridge?.stop()
    }

    @objc private func showPanelFromMenu() {
        panelController?.expandAndShow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

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
