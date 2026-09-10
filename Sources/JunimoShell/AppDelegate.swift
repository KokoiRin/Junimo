import AppKit
import Combine
import JunimoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var shellState: ShellState?
    private var panelController: NotchPanelController?
    private var appBarController: AppBarController?
    private var statusItem: NSStatusItem?
    private var lifecycleWindow: NSWindow?
    private var activityObservation: AnyCancellable?
    private var completionNotificationGate = CodexCompletionNotificationGate()
    private let notificationService = MacCodexCompletionNotificationService()
    private var allowsTermination = false
    private var pendingReopen = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        installLifecycleAnchorWindow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let backend = GoBackendClient()
        let state = ShellState(backend: backend)
        shellState = state
        observeCodexCompletion(in: state)
        state.start()
        deliverNotificationProbeIfRequested()

        let controller = NotchPanelController(state: state)
        panelController = controller
        controller.show()
        appBarController = AppBarController(state: state, backend: backend)
        installStatusItem()
        if pendingReopen { reopenPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenPanel()
        return false
    }

    func reopenPanel() {
        guard let panelController else {
            pendingReopen = true
            return
        }
        pendingReopen = false
        panelController.expandAndShow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityObservation?.cancel()
        activityObservation = nil
        appBarController?.stop()
        appBarController = nil
        shellState?.stop()
        panelController?.stop()
        panelController = nil
        lifecycleWindow?.close()
        lifecycleWindow = nil
    }

    @objc private func showPanelFromMenu() {
        panelController?.expandAndShow()
    }

    @objc private func editQuickLaunchesFromMenu() {
        panelController?.openQuickLaunchConfiguration()
    }

    @objc private func quitFromMenu() {
        allowsTermination = true
        NSApp.terminate(nil)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Junimo")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Junimo", action: #selector(showPanelFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit Quick Launches…", action: #selector(editQuickLaunchesFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示应用栏", action: #selector(toggleAppBar), keyEquivalent: ""))
        let position = NSMenuItem(title: "应用栏位置", action: nil, keyEquivalent: "")
        let positions = NSMenu()
        for placement in AppBarPlacement.allCases {
            let choice = NSMenuItem(title: placement.title, action: #selector(changeAppBarPlacement(_:)), keyEquivalent: "")
            choice.representedObject = placement.rawValue
            choice.target = self
            positions.addItem(choice)
        }
        position.submenu = positions
        menu.addItem(position)
        menu.addItem(NSMenuItem(title: "管理常用应用…", action: #selector(manageAppShortcuts), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Quit Junimo", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleAppBar() { appBarController?.presentation.toggle() }
    @objc private func manageAppShortcuts() { appBarController?.showManager() }
    @objc private func changeAppBarPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = AppBarPlacement(rawValue: raw) else { return }
        appBarController?.presentation.setPlacement(value)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let presentation = appBarController?.presentation else { return }
        menu.items.first { $0.action == #selector(toggleAppBar) }?.state = presentation.enabled ? .on : .off
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) {
            item.state = item.representedObject as? String == presentation.placement.rawValue ? .on : .off
        }
    }

    // observeCodexCompletion 只消费 Go 稳定完成事件，重复 state 轮询不会重复投递。
    private func observeCodexCompletion(in state: ShellState) {
        activityObservation = state.$surfaceState
            .map(\.activity.completionEvent)
            .sink { [weak self] event in
                guard let self, let event = completionNotificationGate.observe(event) else { return }
                notificationService.notifyCompletion(event)
            }
    }

    private func installLifecycleAnchorWindow() {
        guard lifecycleWindow == nil else { return }
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 10, height: 10)
        let window = NSWindow(
            contentRect: NSRect(x: screenFrame.minX + 1, y: screenFrame.minY + 1, width: 2, height: 2),
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
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()
        lifecycleWindow = window
    }

    // 显式环境变量只用于本地端到端验证，正常启动不会产生测试通知。
    private func deliverNotificationProbeIfRequested() {
        guard let threadID = ProcessInfo.processInfo.environment["JUNIMO_NOTIFICATION_TEST_THREAD_ID"] else {
            return
        }
        notificationService.notifyCompletion(
            CodexCompletionEvent(
                id: "junimo-notification-test-\(UUID().uuidString)",
                threadId: threadID,
                title: "Junimo 点击通知测试",
                completedAt: Int64(Date().timeIntervalSince1970)
            )
        )
    }
}
