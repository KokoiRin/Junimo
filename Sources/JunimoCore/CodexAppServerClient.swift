import Foundation
#if canImport(Darwin)
import Darwin
#endif

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

    /// 业务语义：每组 app-server 请求独立握手，并等到关键响应返回或真实超时后才降级。
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

        let outputLock = NSLock()
        var outputData = Data()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            outputLock.lock()
            outputData.append(data)
            outputLock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)

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
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        _ = waitForResponses([0], lock: outputLock, outputData: { outputData }, deadline: min(deadline, Date().addingTimeInterval(3)))
        guard process.isRunning, write(["method": "initialized", "params": [:]], to: stdinPipe) else {
            stop(process: process, stdinPipe: stdinPipe)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        for request in requests {
            guard process.isRunning, write(request, to: stdinPipe) else {
                stop(process: process, stdinPipe: stdinPipe)
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
        }
        _ = waitForResponses(requiredResponseIDs, lock: outputLock, outputData: { outputData }, deadline: deadline)

        stop(process: process, stdinPipe: stdinPipe)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        outputLock.unlock()
        let responseIDs = Self.responseIDs(fromJSONL: output)
        guard requiredResponseIDs.isSubset(of: responseIDs) else {
            return output
        }
        return output
    }

    /// 业务语义：app-server 响应时间取决于账号和网络，adapter 应该等目标响应而不是用固定 sleep 猜测。
    private func waitForResponses(
        _ responseIDs: Set<Int>,
        lock: NSLock,
        outputData: () -> Data,
        deadline: Date
    ) -> Bool {
        while Date() < deadline {
            lock.lock()
            let output = String(data: outputData(), encoding: .utf8) ?? ""
            lock.unlock()
            if responseIDs.isSubset(of: Self.responseIDs(fromJSONL: output)) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func stop(process: Process, stdinPipe: Pipe) {
        stdinPipe.fileHandleForWriting.closeFile()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
#if canImport(Darwin)
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
#endif
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
