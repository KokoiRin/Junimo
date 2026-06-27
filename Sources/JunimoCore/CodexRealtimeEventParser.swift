import Foundation

public enum CodexRealtimeEventParser {
    public static func appServerEvents(fromJSONL jsonl: String, now: Date) -> [CodexRealtimeEvent] {
        jsonl
            .split(whereSeparator: \.isNewline)
            .compactMap { appServerEvent(fromJSON: String($0), now: now) }
    }

    public static func appServerEvent(fromJSON json: String, now: Date) -> CodexRealtimeEvent? {
        guard let object = parseObject(json),
              let method = string(object["method"]) else {
            return nil
        }

        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "account/rateLimitsUpdated", "account/rate_limits_updated":
            return usageEvent(from: params)
        case "thread/statusChanged", "thread/status_changed":
            return threadEvent(from: params, statusOverride: nil, now: now)
        case "turn/completed", "turn.completed", "thread/closed", "thread.closed":
            return threadEvent(from: params, statusOverride: .completed, now: now)
        case "turn/failed", "turn.failed", "error":
            return threadEvent(from: params, statusOverride: .failed, now: now)
        default:
            return nil
        }
    }

    public static func execEvents(fromJSONL jsonl: String, defaultThreadID: String, title: String, now: Date) -> [CodexRealtimeEvent] {
        jsonl
            .split(whereSeparator: \.isNewline)
            .compactMap { execEvent(fromJSON: String($0), defaultThreadID: defaultThreadID, title: title, now: now) }
    }

    public static func execEvent(fromJSON json: String, defaultThreadID: String, title: String, now: Date) -> CodexRealtimeEvent? {
        guard let object = parseObject(json),
              let type = string(object["type"]) ?? string(object["event"]) else {
            return nil
        }

        let status: CodexThreadStatus?
        if type.contains("completed") || type.contains("succeeded") {
            status = .completed
        } else if type.contains("failed") || type == "error" || type.contains("error") {
            status = .failed
        } else if type.contains("started") || type.contains("running") {
            status = .running
        } else {
            status = nil
        }

        guard let status else {
            return nil
        }

        let thread = object["thread"] as? [String: Any]
        let rawID = string(object["thread_id"])
            ?? string(object["threadId"])
            ?? string(thread?["id"])
            ?? defaultThreadID
        let rawTitle = string(object["title"])
            ?? string(thread?["name"])
            ?? string(thread?["preview"])
            ?? title
        let detail = string(object["message"])
            ?? string(object["summary"])
            ?? string((object["error"] as? [String: Any])?["message"])
            ?? type

        return .thread(
            CodexThreadSummary(
                id: prefixed(rawID, prefix: "exec:"),
                title: rawTitle.isEmpty ? title : rawTitle,
                status: status,
                detail: detail,
                updatedAt: now
            )
        )
    }

    private static func usageEvent(from params: [String: Any]) -> CodexRealtimeEvent? {
        guard let usage = CodexStatusParser.usageSnapshot(fromAppServerRateLimitsObject: params) else {
            return nil
        }
        return .usage(usage)
    }

    private static func threadEvent(from params: [String: Any], statusOverride: CodexThreadStatus?, now: Date) -> CodexRealtimeEvent? {
        let thread = params["thread"] as? [String: Any] ?? params
        let rawID = string(thread["id"])
            ?? string(params["threadId"])
            ?? string(params["thread_id"])
            ?? string(params["id"])
        guard let rawID, !rawID.isEmpty else {
            return nil
        }

        let name = string(thread["name"])
        let preview = string(thread["preview"])
        let title = name?.isEmpty == false ? name! : (preview?.isEmpty == false ? String(preview!.prefix(48)) : "Codex \(rawID.prefix(8))")
        let provider = string(thread["modelProvider"]) ?? string(thread["provider"]) ?? "local"
        let cwd = string(thread["cwd"])
        let detail = string(params["detail"])
            ?? string(params["message"])
            ?? string(thread["detail"])
            ?? "\(provider): \(cwd ?? "Codex local thread")"
        let updatedAt = unixDate(thread["updatedAt"])
            ?? unixDate(params["updatedAt"])
            ?? date(from: string(thread["updated_at"]))
            ?? date(from: string(params["updated_at"]))
            ?? now

        return .thread(
            CodexThreadSummary(
                id: prefixed(rawID, prefix: "local:"),
                title: title,
                status: statusOverride ?? threadStatus(fromAppServerStatus: thread["status"] as? [String: Any]),
                detail: detail,
                updatedAt: updatedAt
            )
        )
    }

    /// 业务语义：realtime app-server 状态同样保留 open，避免未知非终态被当作完成或 idle。
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

    private static func prefixed(_ id: String, prefix: String) -> String {
        id.hasPrefix(prefix) ? id : "\(prefix)\(id)"
    }

    private static func parseObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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
