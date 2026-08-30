import Foundation

// 菜单栏应用没有普通窗口，启动前显式关闭系统自动终止以保持刘海入口常驻。
enum AppLifecycleRetainer {
    private static var activity: NSObjectProtocol?
    private static var retained = false

    static func retainBeforeAppRun() {
        guard !retained else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Junimo runs as a persistent menu bar utility."
        )
        ProcessInfo.processInfo.disableAutomaticTermination("Junimo keeps a notch trigger alive.")
        ProcessInfo.processInfo.disableSuddenTermination()
        retained = true
    }
}
