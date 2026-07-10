import Foundation
import JunimoCore

final class MacPomodoroNotificationService {
    func notifyCompletion(for mode: PomodoroMode) {
        let title: String
        let body: String
        switch mode {
        case .focus:
            title = "专注结束"
            body = "休息一下吧。"
        case .rest:
            title = "休息结束"
            body = "准备开始下一轮专注。"
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "display notification \"\(body)\" with title \"\(title)\" sound name \"Glass\""
            ]
            do {
                try process.run()
                process.waitUntilExit()
                LaunchLifecycleDiagnostics.record(
                    process.terminationStatus == 0 ? "pomodoro-notification-scheduled" : "pomodoro-notification-failed",
                    fields: ["mode": mode.rawValue, "status": "\(process.terminationStatus)"]
                )
            } catch {
                LaunchLifecycleDiagnostics.record("pomodoro-notification-failed", fields: [
                    "error": String(describing: error),
                    "mode": mode.rawValue
                ])
            }
        }
    }
}
