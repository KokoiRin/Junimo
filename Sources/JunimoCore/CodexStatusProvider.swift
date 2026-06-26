import Foundation

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

public enum CodexStatusProviderError: Error, Equatable {
    case commandFailed(String)
}

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

    public func querySnapshot(timeout: TimeInterval, now: Date) -> CodexAppServerSnapshot? {
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

        let stdoutLock = NSLock()
        var stdout = ""
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            stdoutLock.lock()
            stdout += text
            stdoutLock.unlock()
        }

        do {
            try process.run()
        } catch {
            return nil
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
            ],
            to: stdinPipe
        )

        var sentStateRequests = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            stdoutLock.lock()
            let currentOutput = stdout
            stdoutLock.unlock()
            let responseIDs = Self.responseIDs(fromJSONL: currentOutput)

            if responseIDs.contains(0) && !sentStateRequests {
                write(["method": "initialized", "params": [:]], to: stdinPipe)
                write(["id": 1, "method": "account/rateLimits/read", "params": NSNull()], to: stdinPipe)
                write(
                    [
                        "id": 2,
                        "method": "thread/list",
                        "params": [
                            "archived": false,
                            "limit": 20,
                            "sortDirection": "desc",
                            "sortKey": "updated_at",
                            "useStateDbOnly": true
                        ]
                    ],
                    to: stdinPipe
                )
                sentStateRequests = true
            }

            if responseIDs.contains(1) && responseIDs.contains(2) {
                break
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        try? stdinPipe.fileHandleForWriting.close()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        stdoutLock.lock()
        let output = stdout
        stdoutLock.unlock()
        return CodexStatusParser.appServerSnapshot(fromJSONL: output, now: now)
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

    private func write(_ object: [String: Any], to pipe: Pipe) {
        let line = Self.jsonLine(object)
        if let data = line.data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
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

public final class CodexCLIStatusProvider {
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

public enum CodexStatusParser {
    public static func snapshot(
        doctorJSON: String?,
        doctorExitCode: Int32?,
        cloudJSON: String?,
        cloudExitCode: Int32?,
        appServerSnapshot: CodexAppServerSnapshot? = nil,
        now: Date
    ) -> CodexMonitorSnapshot {
        let doctor = parseObject(doctorJSON)
        let cloud = parseObject(cloudJSON)

        let usage = appServerSnapshot?.usage ?? usageSnapshot(from: doctor)
        var findings = findings(from: doctor, doctorExitCode: doctorExitCode)
        let cloudThreads = cloudTaskThreads(from: cloud, now: now)
        let appServerThreads = appServerSnapshot?.threads ?? []

        if cloudExitCode == 0 {
            findings.append(
                CodexIntegrationFinding(
                    id: "cloud-list",
                    title: "Cloud tasks",
                    status: .available,
                    detail: cloudThreads.isEmpty ? "No recent cloud tasks returned by codex cloud list." : "\(cloudThreads.count) recent cloud task\(cloudThreads.count == 1 ? "" : "s") loaded."
                )
            )
        } else {
            findings.append(
                CodexIntegrationFinding(
                    id: "cloud-list",
                    title: "Cloud tasks",
                    status: .degraded,
                    detail: "codex cloud list --json did not return a usable task snapshot."
                )
            )
        }

        if let appServerSnapshot {
            findings.append(contentsOf: appServerSnapshot.findings)
        } else {
            findings.append(
                CodexIntegrationFinding(
                    id: "app-server-rate-limits",
                    title: "Live quota",
                    status: .needsSetup,
                    detail: "Next adapter should call account/rateLimits/read over codex app-server."
                )
            )
        }

        return CodexMonitorSnapshot(
            usage: usage,
            threads: mergedThreads(appServerThreads + cloudThreads),
            findings: findings,
            refreshedAt: now
        )
    }

    public static func appServerSnapshot(fromJSONL jsonl: String, now: Date) -> CodexAppServerSnapshot {
        let messages = jsonl
            .split(whereSeparator: \.isNewline)
            .compactMap { parseObject(String($0)) }
        let rateLimitResponse = messages.first { int($0["id"]) == 1 }
        let threadListResponse = messages.first { int($0["id"]) == 2 }

        let usage = (rateLimitResponse?["result"] as? [String: Any]).flatMap { result in
            usageSnapshot(fromAppServerRateLimits: result)
        }
        var findings: [CodexIntegrationFinding] = []
        findings.append(
            CodexIntegrationFinding(
                id: "app-server-rate-limits",
                title: "Live quota",
                status: usage == nil ? .degraded : .available,
                detail: usage == nil ? jsonRPCErrorDetail(from: rateLimitResponse, fallback: "app-server did not return rate limits.") : "Loaded live account/rateLimits/read snapshot."
            )
        )

        let threads = appServerThreads(from: threadListResponse?["result"] as? [String: Any], now: now)
        findings.append(
            CodexIntegrationFinding(
                id: "app-server-threads",
                title: "Local threads",
                status: threadListResponse == nil ? .degraded : .available,
                detail: threadListResponse == nil ? "app-server did not return thread/list." : "\(threads.count) local thread\(threads.count == 1 ? "" : "s") loaded."
            )
        )

        return CodexAppServerSnapshot(usage: usage, threads: threads, findings: findings)
    }

    public static func usageSnapshot(fromAppServerRateLimitsJSON json: String, now: Date = Date()) -> CodexUsageSnapshot? {
        guard let object = parseObject(json) else {
            return nil
        }
        return usageSnapshot(fromAppServerRateLimits: object)
    }

    private static func usageSnapshot(fromAppServerRateLimits object: [String: Any]) -> CodexUsageSnapshot? {
        let rateLimitsByLimitId = object["rateLimitsByLimitId"] as? [String: Any]
        let codexRateLimits = rateLimitsByLimitId?["codex"] as? [String: Any]
        let rateLimits = codexRateLimits ?? object["rateLimits"] as? [String: Any]
        guard let rateLimits else {
            return nil
        }

        let plan = rateLimits["planType"] as? String
        let primary = rateLimitWindow(from: rateLimits["primary"] as? [String: Any], label: "Primary")
        let secondary = rateLimitWindow(from: rateLimits["secondary"] as? [String: Any], label: "Secondary")
        let credits = rateLimits["credits"] as? [String: Any]

        return CodexUsageSnapshot(
            status: .available,
            planLabel: plan?.localizedCapitalized ?? "Codex quota",
            detail: usageDetail(primary: primary, secondary: secondary),
            source: "Codex app-server",
            primaryWindow: primary,
            secondaryWindow: secondary,
            creditsBalance: credits?["balance"] as? String
        )
    }

    private static func usageSnapshot(from doctor: [String: Any]?) -> CodexUsageSnapshot {
        let auth = check("auth.credentials", in: doctor)
        let authStatus = string(auth?["status"])
        let authDetails = auth?["details"] as? [String: Any]
        let authMode = string(authDetails?["stored auth mode"]) ?? "unknown auth"
        let appServer = check("app_server.status", in: doctor)
        let appServerDetails = appServer?["details"] as? [String: Any]
        let appServerStatus = string(appServerDetails?["status"]) ?? "unknown"

        if authStatus != "ok" {
            return CodexUsageSnapshot(
                status: .needsSetup,
                planLabel: "Codex quota",
                detail: "Codex auth is not configured; run codex login before quota can be read.",
                source: "codex doctor"
            )
        }

        if appServerStatus == "running" {
            return CodexUsageSnapshot(
                status: .needsSetup,
                planLabel: "Codex quota",
                detail: "App-server is running; connect and call account/rateLimits/read for live limits.",
                source: "codex doctor"
            )
        }

        return CodexUsageSnapshot(
            status: .needsSetup,
            planLabel: "Codex quota",
            detail: "Auth is \(authMode); start codex app-server to read live rate-limit windows.",
            source: "codex doctor"
        )
    }

    private static func findings(from doctor: [String: Any]?, doctorExitCode: Int32?) -> [CodexIntegrationFinding] {
        guard let doctor else {
            return [
                CodexIntegrationFinding(
                    id: "doctor",
                    title: "Codex diagnostics",
                    status: .degraded,
                    detail: "codex doctor --json did not return a usable diagnostic snapshot."
                )
            ]
        }

        var output: [CodexIntegrationFinding] = []
        let version = string(doctor["codexVersion"]) ?? "unknown"
        let overall = string(doctor["overallStatus"]) ?? "unknown"
        output.append(
            CodexIntegrationFinding(
                id: "doctor",
                title: "Codex CLI",
                status: doctorExitCode == 0 ? .available : .degraded,
                detail: "Version \(version); doctor status \(overall)."
            )
        )

        appendCheckFinding(
            id: "auth",
            title: "Authentication",
            checkID: "auth.credentials",
            doctor: doctor,
            into: &output
        )
        appendCheckFinding(
            id: "app-server",
            title: "App server",
            checkID: "app_server.status",
            doctor: doctor,
            into: &output
        )
        appendCheckFinding(
            id: "thread-inventory",
            title: "Thread inventory",
            checkID: "state.rollout_db_parity",
            doctor: doctor,
            into: &output
        )
        appendCheckFinding(
            id: "network",
            title: "Network",
            checkID: "network.provider_reachability",
            doctor: doctor,
            into: &output
        )

        return output
    }

    private static func appendCheckFinding(
        id: String,
        title: String,
        checkID: String,
        doctor: [String: Any],
        into output: inout [CodexIntegrationFinding]
    ) {
        guard let check = check(checkID, in: doctor) else {
            output.append(CodexIntegrationFinding(id: id, title: title, status: .degraded, detail: "\(checkID) missing from codex doctor."))
            return
        }
        let statusText = string(check["status"]) ?? "unknown"
        let summary = string(check["summary"]) ?? "No summary"
        output.append(
            CodexIntegrationFinding(
                id: id,
                title: title,
                status: capabilityStatus(fromDoctorStatus: statusText),
                detail: summary
            )
        )
    }

    private static func cloudTaskThreads(from cloud: [String: Any]?, now: Date) -> [CodexThreadSummary] {
        guard let tasks = cloud?["tasks"] as? [[String: Any]] else {
            return []
        }
        return tasks.prefix(8).map { task in
            let id = string(task["id"]) ?? UUID().uuidString
            let title = string(task["title"]) ?? "Codex cloud task"
            let statusText = string(task["status"]) ?? "unknown"
            let environment = string(task["environment_label"]) ?? string(task["environment_id"]) ?? "cloud"
            let summary = string(task["summary"]) ?? statusText
            return CodexThreadSummary(
                id: "cloud:\(id)",
                title: title.isEmpty ? "Codex cloud task" : title,
                status: threadStatus(fromCloudStatus: statusText),
                detail: "\(environment): \(summary)",
                updatedAt: date(from: string(task["updated_at"])) ?? now
            )
        }
    }

    private static func appServerThreads(from result: [String: Any]?, now: Date) -> [CodexThreadSummary] {
        guard let threads = result?["data"] as? [[String: Any]] else {
            return []
        }
        return threads.prefix(8).map { thread in
            let id = string(thread["id"]) ?? UUID().uuidString
            let name = string(thread["name"])
            let preview = string(thread["preview"])
            let cwd = string(thread["cwd"])
            let provider = string(thread["modelProvider"]) ?? "local"
            let status = threadStatus(fromAppServerStatus: thread["status"] as? [String: Any])
            let updatedAt = unixDate(thread["updatedAt"]) ?? now

            return CodexThreadSummary(
                id: "local:\(id)",
                title: threadTitle(name: name, preview: preview, id: id),
                status: status,
                detail: "\(provider): \(cwd ?? "Codex local thread")",
                updatedAt: updatedAt
            )
        }
    }

    private static func threadTitle(name: String?, preview: String?, id: String) -> String {
        if let name, !name.isEmpty {
            return name
        }
        if let preview, !preview.isEmpty {
            return String(preview.prefix(48))
        }
        return "Codex \(id.prefix(8))"
    }

    private static func threadStatus(fromAppServerStatus object: [String: Any]?) -> CodexThreadStatus {
        let type = string(object?["type"]) ?? "idle"
        switch type {
        case "active":
            let flags = object?["activeFlags"] as? [String] ?? []
            return flags.isEmpty ? .running : .waiting
        case "systemError":
            return .failed
        case "idle":
            return .idle
        default:
            return .idle
        }
    }

    private static func mergedThreads(_ threads: [CodexThreadSummary]) -> [CodexThreadSummary] {
        var seen = Set<String>()
        var merged: [CodexThreadSummary] = []
        for thread in threads.sorted(by: { $0.updatedAt > $1.updatedAt }) where !seen.contains(thread.id) {
            seen.insert(thread.id)
            merged.append(thread)
            if merged.count >= 8 {
                break
            }
        }
        return merged
    }

    private static func rateLimitWindow(from object: [String: Any]?, label: String) -> CodexUsageWindow? {
        guard let object else {
            return nil
        }
        return CodexUsageWindow(
            label: label,
            usedPercent: int(object["usedPercent"]),
            resetsAt: unixDate(object["resetsAt"]),
            durationMinutes: int(object["windowDurationMins"])
        )
    }

    private static func usageDetail(primary: CodexUsageWindow?, secondary: CodexUsageWindow?) -> String {
        if let primary, let used = primary.usedPercent {
            return "\(max(0, 100 - used))% left in primary window"
        }
        if let secondary, let used = secondary.usedPercent {
            return "\(max(0, 100 - used))% left in secondary window"
        }
        return "Live rate-limit snapshot loaded"
    }

    private static func capabilityStatus(fromDoctorStatus status: String) -> CodexCapabilityStatus {
        switch status {
        case "ok": .available
        case "warning": .degraded
        case "fail": .degraded
        default: .degraded
        }
    }

    private static func threadStatus(fromCloudStatus status: String) -> CodexThreadStatus {
        let normalized = status.lowercased()
        if normalized.contains("fail") || normalized.contains("error") || normalized.contains("cancel") {
            return .failed
        }
        if normalized.contains("complete") || normalized.contains("succeed") || normalized.contains("done") || normalized.contains("merged") {
            return .completed
        }
        if normalized.contains("run") || normalized.contains("progress") || normalized.contains("queue") || normalized.contains("pending") {
            return .running
        }
        return .idle
    }

    private static func check(_ id: String, in doctor: [String: Any]?) -> [String: Any]? {
        guard let checks = doctor?["checks"] as? [String: Any] else {
            return nil
        }
        return checks[id] as? [String: Any]
    }

    private static func parseObject(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func jsonRPCErrorDetail(from response: [String: Any]?, fallback: String) -> String {
        guard let error = response?["error"] as? [String: Any] else {
            return fallback
        }
        return string(error["message"]) ?? fallback
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func unixDate(_ value: Any?) -> Date? {
        guard let timestamp = int(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
