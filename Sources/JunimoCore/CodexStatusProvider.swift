import Foundation

/// Codex snapshot provider composition.
/// This file combines command runner output, app-server snapshots, and pure parsers into monitor snapshots.
public final class CodexCLIStatusProvider: CodexMonitorSnapshotProviding {
    private let runner: CodexCommandRunning
    private let appServerClient: CodexAppServerQuerying?

    public init(
        runner: CodexCommandRunning = ProcessCodexCommandRunner(),
        appServerClient: CodexAppServerQuerying? = ProcessCodexAppServerClient()
    ) {
        self.runner = runner
        self.appServerClient = appServerClient
    }

    public func loadSnapshot(now: Date = Date()) -> CodexMonitorSnapshot {
        let doctor = runDoctor()
        let cloudTasks = runCloudTasks()
        let appServer = appServerClient?.querySnapshot(timeout: 8, now: now)
        return CodexStatusParser.snapshot(
            doctorJSON: doctor?.stdout,
            doctorExitCode: doctor?.exitCode,
            cloudJSON: cloudTasks?.stdout,
            cloudExitCode: cloudTasks?.exitCode,
            appServerSnapshot: appServer,
            now: now
        )
    }

    private func runDoctor() -> CodexCommandResult? {
        try? runner.runCodex(arguments: ["doctor", "--json"], timeout: 12)
    }

    private func runCloudTasks() -> CodexCommandResult? {
        try? runner.runCodex(arguments: ["cloud", "list", "--json", "--limit", "20"], timeout: 12)
    }
}
