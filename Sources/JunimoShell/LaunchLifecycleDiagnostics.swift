import Darwin
import Foundation

enum LaunchLifecycleDiagnostics {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func record(_ event: String, fields: [String: String] = [:]) {
        let url = URL(fileURLWithPath: path())
        let payload = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let prefix = "\(formatter.string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) event=\(event)"
        let line = payload.isEmpty ? "\(prefix)\n" : "\(prefix) \(payload)\n"

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

    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["JUNIMO_LAUNCH_LOG_PATH"], !override.isEmpty {
            return override
        }
        return "\(NSHomeDirectory())/Library/Application Support/Junimo/launch.log"
    }
}

enum AppLifecycleRetainer {
    private static var activity: NSObjectProtocol?
    private static var retained = false
    private static var signalSources: [DispatchSourceSignal] = []

    static func retainBeforeAppRun() {
        guard !retained else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Junimo runs as a persistent menu bar utility."
        )
        ProcessInfo.processInfo.disableAutomaticTermination("Junimo keeps a notch trigger alive.")
        ProcessInfo.processInfo.disableSuddenTermination()
        retained = true
        installExitDiagnostics()
    }

    private static func installExitDiagnostics() {
        atexit {
            LaunchLifecycleDiagnostics.record("process-atexit")
        }

        for signalNumber in [SIGTERM, SIGHUP, SIGINT, SIGQUIT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                LaunchLifecycleDiagnostics.record("process-signal", fields: [
                    "signal": "\(signalNumber)"
                ])
                exit(128 + signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
