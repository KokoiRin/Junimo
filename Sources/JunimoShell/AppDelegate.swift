import AppKit
import Combine
import JunimoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellState: ShellState?
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var lifecycleWindow: NSWindow?
    private var pomodoroObservation: AnyCancellable?
    private var completionNotificationGate = PomodoroCompletionNotificationGate()
    private let notificationService = MacPomodoroNotificationService()
    private var allowsTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchLifecycleDiagnostics.record("application-will-finish-launching")
        installLifecycleAnchorWindow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLifecycleDiagnostics.record("application-did-finish-launching")
        NSApp.setActivationPolicy(.accessory)

        let state = ShellState()
        shellState = state
        observePomodoroCompletion(in: state)
        state.start()

        let controller = NotchPanelController(state: state)
        panelController = controller
        controller.show()

        installStatusItem()
        LaunchLifecycleDiagnostics.record("notch-panel-shown", fields: [
            "visible": "\(controller.isVisible)"
        ])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        pomodoroObservation?.cancel()
        pomodoroObservation = nil
        shellState?.stop()
        lifecycleWindow?.close()
        lifecycleWindow = nil
        LaunchLifecycleDiagnostics.record("application-will-terminate")
    }

    @objc private func showPanelFromMenu() {
        panelController?.expandAndShow()
    }

    @objc private func quitFromMenu() {
        allowsTermination = true
        LaunchLifecycleDiagnostics.record("quit-requested-from-menu")
        NSApp.terminate(nil)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Junimo")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Junimo", action: #selector(showPanelFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Junimo", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func observePomodoroCompletion(in state: ShellState) {
        pomodoroObservation = state.$surfaceState
            .map(\.pomodoro.completionEvent)
            .sink { [weak self] event in
                guard let self,
                      let mode = completionNotificationGate.observe(event) else { return }
                notificationService.notifyCompletion(for: mode)
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
}
