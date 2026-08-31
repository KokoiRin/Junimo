import AppKit
import Combine
import JunimoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellState: ShellState?
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var lifecycleWindow: NSWindow?
    private var activityObservation: AnyCancellable?
    private var completionNotificationGate = CodexCompletionNotificationGate()
    private let notificationService = MacCodexCompletionNotificationService()
    private var allowsTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        installLifecycleAnchorWindow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = ShellState()
        shellState = state
        observeCodexCompletion(in: state)
        state.start()
        deliverNotificationProbeIfRequested()

        let controller = NotchPanelController(state: state)
        panelController = controller
        controller.show()
        installStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityObservation?.cancel()
        activityObservation = nil
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
        menu.addItem(NSMenuItem(title: "Quit Junimo", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
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
