import Foundation

enum LaunchLifecycleDiagnostics {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 业务语义：启动诊断必须落到用户可读位置，方便远端机器排查“启动过但随后退出”的生命周期问题。
    static func record(_ event: String, fields: [String: String] = [:]) {
        let url = logURL()
        let line = serializedLine(event: event, fields: fields)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            fputs("Junimo launch diagnostics write failed: \(error)\n", stderr)
        }
    }

    /// 业务语义：日志路径可由环境覆盖；默认放在 Application Support，便于用户直接打包发回。
    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["JUNIMO_LAUNCH_LOG_PATH"], !override.isEmpty {
            return override
        }
        return "\(NSHomeDirectory())/Library/Application Support/Junimo/launch.log"
    }

    private static func logURL() -> URL {
        URL(fileURLWithPath: path())
    }

    private static func serializedLine(event: String, fields: [String: String]) -> String {
        let payload = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let prefix = "\(formatter.string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) event=\(event)"
        return payload.isEmpty ? "\(prefix)\n" : "\(prefix) \(payload)\n"
    }
}

enum AppLifecycleRetainer {
    static let reason = "Junimo runs as a persistent menu bar utility."
    private static var retained = false

    /// 业务语义：termination 抑制必须早于 NSApplication 启动流程，避免 AppKit 在无普通窗口时安排自动回收。
    static func retainBeforeAppRun() {
        guard !retained else { return }
        ProcessInfo.processInfo.disableAutomaticTermination(reason)
        ProcessInfo.processInfo.disableSuddenTermination()
        retained = true
        LaunchLifecycleDiagnostics.record("process-retained-before-app-run")
    }
}
