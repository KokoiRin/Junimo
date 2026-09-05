import AppKit

@main
struct JunimoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let instance = SingleInstanceController { [weak delegate] in delegate?.reopenPanel() }
        do {
            guard try instance.acquireOrReopen() else { return }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Junimo 无法启动"
            alert.informativeText = "无法确认应用运行状态，请稍后重试。\n\(error.localizedDescription)"
            alert.runModal()
            return
        }
        AppLifecycleRetainer.retainBeforeAppRun()
        app.delegate = delegate
        withExtendedLifetime((instance, delegate)) { app.run() }
    }
}
