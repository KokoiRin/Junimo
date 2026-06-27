import Foundation

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
        return usageSnapshot(fromAppServerRateLimitsObject: object)
    }

    public static func usageSnapshot(fromAppServerRateLimitsObject object: [String: Any]) -> CodexUsageSnapshot? {
        usageSnapshot(fromAppServerRateLimits: object)
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

    /// 业务语义：app-server 线程要先完整进入生命周期归一化，不能在解析阶段截断。
    private static func appServerThreads(from result: [String: Any]?, now: Date) -> [CodexThreadSummary] {
        guard let threads = result?["data"] as? [[String: Any]] else {
            return []
        }
        return threads.map { thread in
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

    /// 业务语义：notLoaded/idle 是非终态 open work，不能压成 quota-only idle。
    private static func threadStatus(fromAppServerStatus object: [String: Any]?) -> CodexThreadStatus {
        let type = string(object?["type"]) ?? "idle"
        switch type {
        case "active":
            let flags = object?["activeFlags"] as? [String] ?? []
            return flags.isEmpty ? .running : .waiting
        case "systemError":
            return .failed
        case "completed", "succeeded", "done", "closed":
            return .completed
        case "failed", "error", "cancelled", "canceled":
            return .failed
        case "idle", "notLoaded":
            return .open
        default:
            return .open
        }
    }

    /// 业务语义：合并后的可见列表按生命周期优先级截断，active/open 不会被普通历史线程挤掉。
    private static func mergedThreads(_ threads: [CodexThreadSummary]) -> [CodexThreadSummary] {
        var seen = Set<String>()
        var merged: [CodexThreadSummary] = []
        let reduced = CodexThreadLifecycleReducer.reduce(threads: threads)
        for thread in reduced.visibleThreads where !seen.contains(thread.id) {
            seen.insert(thread.id)
            merged.append(thread)
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

    /// 业务语义：cloud 未知状态保持为 open，只有明确终态才触发 terminal。
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
        return .open
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
