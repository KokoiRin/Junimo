import AppKit

@main
struct JunimoMain {
    static func main() {
        AppLifecycleRetainer.retainBeforeAppRun()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
