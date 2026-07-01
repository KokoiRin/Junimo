import Foundation

public final class ProcessCodexAppServerClient: CodexAppServerQuerying {
    private let executableURL: URL
    private let workingDirectoryURL: URL

    public init(
        executableURL: URL = ProcessCodexCommandRunner.defaultCodexExecutableURL(),
        workingDirectoryURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    /// 业务语义：短连接 probe 必须完整读取 quota 和 thread/list 响应，尤其是大线程列表。
    public func querySnapshot(timeout: TimeInterval, now: Date) -> CodexAppServerSnapshot? {
        let output = queryJSONL(
            timeout: timeout,
            requests: [
                ["id": 1, "method": "account/rateLimits/read", "params": NSNull()],
                [
                    "id": 2,
                    "method": "thread/list",
                    "params": [
                        "archived": false,
                        "limit": 50,
                        "sortDirection": "desc",
                        "sortKey": "updated_at",
                        "useStateDbOnly": true
                    ]
                ]
            ],
            requiredResponseIDs: [1, 2]
        )
        guard let output, !output.isEmpty else {
            return nil
        }
        return CodexStatusParser.appServerSnapshot(fromJSONL: output, now: now)
    }

    /// 业务语义：每组 app-server 请求独立握手，避免 quota 与 thread/list 互相影响。
    private func queryJSONL(timeout: TimeInterval, requests: [[String: Any]], requiredResponseIDs: Set<Int>) -> String? {
        BrokenPipeGuard.install()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = executableURL.path == "/usr/bin/env" ? ["codex", "app-server", "--stdio"] : ["app-server", "--stdio"]
        process.currentDirectoryURL = workingDirectoryURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        guard write(
            [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "junimo",
                        "title": "Junimo",
                        "version": "0.1.0"
                    ],
                    "capabilities": [
                        "experimentalApi": true
                    ]
                ]
            ],
            to: stdinPipe
        ) else {
            stop(process: process, stdinPipe: stdinPipe)
            return nil
        }

        Thread.sleep(forTimeInterval: min(0.5, timeout))
        guard process.isRunning, write(["method": "initialized", "params": [:]], to: stdinPipe) else {
            stop(process: process, stdinPipe: stdinPipe)
            return nil
        }
        for request in requests {
            guard process.isRunning, write(request, to: stdinPipe) else {
                stop(process: process, stdinPipe: stdinPipe)
                return nil
            }
        }
        Thread.sleep(forTimeInterval: min(max(timeout - 0.5, 0.5), 4.0))

        stop(process: process, stdinPipe: stdinPipe)
        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let responseIDs = Self.responseIDs(fromJSONL: output)
        guard requiredResponseIDs.isSubset(of: responseIDs) else {
            return output
        }
        return output
    }

    private func stop(process: Process, stdinPipe: Pipe) {
        stdinPipe.fileHandleForWriting.closeFile()
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
    }

    private static func responseIDs(fromJSONL jsonl: String) -> Set<Int> {
        Set(
            jsonl
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    guard let data = String(line).data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return nil
                    }
                    return object["id"] as? Int
                }
        )
    }

    private func write(_ object: [String: Any], to pipe: Pipe) -> Bool {
        let line = Self.jsonLine(object)
        guard let data = line.data(using: .utf8) else {
            return false
        }
        return BrokenPipeGuard.write(data, to: pipe.fileHandleForWriting)
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text + "\n"
    }
}
