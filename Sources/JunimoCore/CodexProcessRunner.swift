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
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["JUNIMO_CODEX_EXECUTABLE"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        if let discovered = codexExecutableCandidates(fileManager: fileManager).first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) {
            return discovered
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func codexExecutableCandidates(fileManager: FileManager) -> [URL] {
        var candidates: [URL] = []
        let mainBundle = Bundle.main.bundleURL
        if mainBundle.pathExtension == "app" {
            candidates.append(mainBundle.appendingPathComponent("Contents/Resources/codex"))
            candidates.append(
                mainBundle
                    .deletingLastPathComponent()
                    .appendingPathComponent("Codex.app/Contents/Resources/codex")
            )
        }

        let appDirectoryMasks: FileManager.SearchPathDomainMask = [.userDomainMask, .localDomainMask, .systemDomainMask]
        for appDirectory in fileManager.urls(for: .applicationDirectory, in: appDirectoryMasks) {
            candidates.append(appDirectory.appendingPathComponent("Codex.app/Contents/Resources/codex"))
        }

        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/codex")
        )

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        for entry in pathEntries where !entry.isEmpty {
            candidates.append(URL(fileURLWithPath: entry).appendingPathComponent("codex"))
        }

        return candidates.uniquedByPath()
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

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
