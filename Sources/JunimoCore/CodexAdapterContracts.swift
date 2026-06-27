import Foundation

/// Codex adapter contracts and typed protocol results.
/// These types define the boundary between external Codex I/O and Junimo feature state.
public struct CodexCommandResult: Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CodexCommandRunning {
    func runCodex(arguments: [String], timeout: TimeInterval) throws -> CodexCommandResult
}

public protocol CodexAppServerQuerying {
    func querySnapshot(timeout: TimeInterval, now: Date) -> CodexAppServerSnapshot?
}

public protocol CodexMonitorSnapshotProviding {
    func loadSnapshot(now: Date) -> CodexMonitorSnapshot
}

public protocol CodexRealtimeEventStreaming: AnyObject {
    func start(
        onEvent: @escaping (CodexRealtimeEvent) -> Void,
        onFinished: @escaping (CodexIntegrationFinding?) -> Void
    )
    func stop()
}

public enum CodexRealtimeEvent: Equatable {
    case usage(CodexUsageSnapshot)
    case thread(CodexThreadSummary)
    case finding(CodexIntegrationFinding)
}

public enum CodexStatusProviderError: Error, Equatable {
    case commandFailed(String)
}

public struct CodexAppServerSnapshot: Equatable {
    public var usage: CodexUsageSnapshot?
    public var threads: [CodexThreadSummary]
    public var findings: [CodexIntegrationFinding]

    public init(usage: CodexUsageSnapshot?, threads: [CodexThreadSummary], findings: [CodexIntegrationFinding]) {
        self.usage = usage
        self.threads = threads
        self.findings = findings
    }
}
