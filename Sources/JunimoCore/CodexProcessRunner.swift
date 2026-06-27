import Foundation

public final class ProcessCodexCommandRunner: CodexCommandRunning {
    let executableURL: URL
    private let workingDirectoryURL: URL

    public init(
        executableURL: URL = ProcessCodexCommandRunner.defaultCodexExecutableURL(),
        workingDirectoryURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    public static func defaultCodexExecutableURL() -> URL {
        let homeCodex = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")
        if FileManager.default.fileExists(atPath: homeCodex.path) {
            return homeCodex
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    public func runCodex(arguments: [String], timeout: TimeInterval) throws -> CodexCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = executableURL.path == "/usr/bin/env" ? ["codex"] + arguments : arguments
        process.currentDirectoryURL = workingDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CodexCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
