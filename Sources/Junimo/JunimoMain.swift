import AppKit

@main
struct JunimoMain {
    static func main() {
        AppLifecycleRetainer.retainBeforeAppRun()
        LaunchLifecycleDiagnostics.record("main-before-shared-application")
        let app = NSApplication.shared
        LaunchLifecycleDiagnostics.record("main-created-shared-application")
        let delegate = AppDelegate()
        app.delegate = delegate
        LaunchLifecycleDiagnostics.record("main-before-run")
        app.run()
        LaunchLifecycleDiagnostics.record("main-after-run")
    }
}
