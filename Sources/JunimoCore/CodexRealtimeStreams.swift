import Foundation

public final class ProcessCodexAppServerEventStream: CodexRealtimeEventStreaming {
    private let executableURL: URL
    private let workingDirectoryURL: URL
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var pendingOutput = ""
    private var sentInitialized = false
    private var isStopping = false
    private var onEvent: ((CodexRealtimeEvent) -> Void)?
    private var onFinished: ((CodexIntegrationFinding?) -> Void)?

    public init(
        executableURL: URL = ProcessCodexCommandRunner.defaultCodexExecutableURL(),
        workingDirectoryURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    public func start(
        onEvent: @escaping (CodexRealtimeEvent) -> Void,
        onFinished: @escaping (CodexIntegrationFinding?) -> Void
    ) {
        BrokenPipeGuard.install()
        lock.lock()
        if process != nil {
            lock.unlock()
            return
        }
        isStopping = false
        self.onEvent = onEvent
        self.onFinished = onFinished
        lock.unlock()

        let newProcess = Process()
        newProcess.executableURL = executableURL
        newProcess.arguments = executableURL.path == "/usr/bin/env" ? ["codex", "app-server", "--stdio"] : ["app-server", "--stdio"]
        newProcess.currentDirectoryURL = workingDirectoryURL

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        newProcess.standardInput = stdin
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.handleOutput(text)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        newProcess.terminationHandler = { [weak self] process in
            self?.handleTermination(exitCode: process.terminationStatus)
        }

        lock.lock()
        process = newProcess
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        lock.unlock()

        do {
            try newProcess.run()
        } catch {
            lock.lock()
            process = nil
            stdinPipe = nil
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stdoutPipe = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe = nil
            lock.unlock()
            finish(
                CodexIntegrationFinding(
                    id: "app-server-realtime",
                    title: "Realtime Codex events",
                    status: .degraded,
                    detail: "Could not start codex app-server realtime stream."
                )
            )
            return
        }

        write(
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
            ]
        )
    }

    public func stop() {
        lock.lock()
        let runningProcess = process
        isStopping = true
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        onEvent = nil
        onFinished = nil
        pendingOutput = ""
        sentInitialized = false
        lock.unlock()

        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func handleOutput(_ text: String) {
        var lines: [String] = []
        lock.lock()
        pendingOutput += text
        while let newline = pendingOutput.firstIndex(where: \.isNewline) {
            lines.append(String(pendingOutput[..<newline]))
            pendingOutput.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines where !line.isEmpty {
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        if responseIDs(fromJSONL: line).contains(0) {
            sendInitializedIfNeeded()
        }

        if let event = CodexRealtimeEventParser.appServerEvent(fromJSON: line, now: Date()) {
            lock.lock()
            let callback = onEvent
            lock.unlock()
            callback?(event)
        }
    }

    private func sendInitializedIfNeeded() {
        lock.lock()
        let shouldSend = !sentInitialized
        sentInitialized = true
        lock.unlock()

        guard shouldSend else {
            return
        }

        write(["method": "initialized", "params": [:]])
    }

    private func handleTermination(exitCode: Int32) {
        lock.lock()
        let stopped = isStopping
        lock.unlock()

        let finding: CodexIntegrationFinding?
        if exitCode == 0 || stopped {
            finding = nil
        } else {
            finding = CodexIntegrationFinding(
                id: "app-server-realtime",
                title: "Realtime Codex events",
                status: .degraded,
                detail: "codex app-server realtime stream exited with code \(exitCode)."
            )
        }
        finish(finding)
    }

    private func finish(_ finding: CodexIntegrationFinding?) {
        lock.lock()
        let callback = onFinished
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        pendingOutput = ""
        sentInitialized = false
        isStopping = false
        lock.unlock()
        callback?(finding)
    }

    private func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line += "\n"

        lock.lock()
        let handle = stdinPipe?.fileHandleForWriting
        lock.unlock()
        guard let data = line.data(using: .utf8), let handle else {
            return
        }
        if !BrokenPipeGuard.write(data, to: handle) {
            finish(
                CodexIntegrationFinding(
                    id: "app-server-realtime",
                    title: "Realtime Codex events",
                    status: .degraded,
                    detail: "Codex realtime stream disconnected while Junimo was writing to it."
                )
            )
        }
    }

    private func responseIDs(fromJSONL jsonl: String) -> Set<Int> {
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
}

public final class ProcessCodexExecEventStream: CodexRealtimeEventStreaming {
    private let executableURL: URL
    private let workingDirectoryURL: URL
    private let arguments: [String]
    private let defaultThreadID: String
    private let title: String
    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var pendingOutput = ""
    private var isStopping = false
    private var onEvent: ((CodexRealtimeEvent) -> Void)?
    private var onFinished: ((CodexIntegrationFinding?) -> Void)?

    public init(
        arguments: [String],
        defaultThreadID: String = UUID().uuidString,
        title: String = "Junimo Codex",
        executableURL: URL = ProcessCodexCommandRunner.defaultCodexExecutableURL(),
        workingDirectoryURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) {
        self.arguments = arguments
        self.defaultThreadID = defaultThreadID
        self.title = title
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    public func start(
        onEvent: @escaping (CodexRealtimeEvent) -> Void,
        onFinished: @escaping (CodexIntegrationFinding?) -> Void
    ) {
        lock.lock()
        if process != nil {
            lock.unlock()
            return
        }
        isStopping = false
        self.onEvent = onEvent
        self.onFinished = onFinished
        lock.unlock()

        let newProcess = Process()
        newProcess.executableURL = executableURL
        let execArguments = ["exec", "--json"] + arguments
        newProcess.arguments = executableURL.path == "/usr/bin/env" ? ["codex"] + execArguments : execArguments
        newProcess.currentDirectoryURL = workingDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.handleOutput(text)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        newProcess.terminationHandler = { [weak self] process in
            self?.handleTermination(exitCode: process.terminationStatus)
        }

        lock.lock()
        process = newProcess
        stdoutPipe = stdout
        stderrPipe = stderr
        lock.unlock()

        do {
            try newProcess.run()
        } catch {
            lock.lock()
            process = nil
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stdoutPipe = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe = nil
            lock.unlock()
            finish(
                CodexIntegrationFinding(
                    id: "exec-json-stream",
                    title: "Codex exec stream",
                    status: .degraded,
                    detail: "Could not start codex exec --json stream."
                )
            )
            return
        }
    }

    public func stop() {
        lock.lock()
        let runningProcess = process
        isStopping = true
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        onEvent = nil
        onFinished = nil
        pendingOutput = ""
        lock.unlock()

        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func handleOutput(_ text: String) {
        var lines: [String] = []
        lock.lock()
        pendingOutput += text
        while let newline = pendingOutput.firstIndex(where: \.isNewline) {
            lines.append(String(pendingOutput[..<newline]))
            pendingOutput.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines where !line.isEmpty {
            if let event = CodexRealtimeEventParser.execEvent(
                fromJSON: line,
                defaultThreadID: defaultThreadID,
                title: title,
                now: Date()
            ) {
                lock.lock()
                let callback = onEvent
                lock.unlock()
                callback?(event)
            }
        }
    }

    private func handleTermination(exitCode: Int32) {
        lock.lock()
        let stopped = isStopping
        lock.unlock()

        if exitCode != 0 && !stopped {
            lock.lock()
            let callback = onEvent
            lock.unlock()
            callback?(
                .thread(
                    CodexThreadSummary(
                        id: "exec:\(defaultThreadID)",
                        title: title,
                        status: .failed,
                        detail: "codex exec --json exited with code \(exitCode).",
                        updatedAt: Date()
                    )
                )
            )
        }

        let finding: CodexIntegrationFinding?
        if exitCode == 0 || stopped {
            finding = nil
        } else {
            finding = CodexIntegrationFinding(
                id: "exec-json-stream",
                title: "Codex exec stream",
                status: .degraded,
                detail: "codex exec --json exited with code \(exitCode)."
            )
        }
        finish(finding)
    }

    private func finish(_ finding: CodexIntegrationFinding?) {
        lock.lock()
        let callback = onFinished
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        pendingOutput = ""
        isStopping = false
        lock.unlock()
        callback?(finding)
    }
}
