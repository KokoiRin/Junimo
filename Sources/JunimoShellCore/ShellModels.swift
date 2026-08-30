import Foundation

public enum CodexUsageStatus: String, Codable, Equatable {
    case loading
    case available
    case unavailable
}

public struct CodexUsageWindow: Codable, Equatable {
    public var remainingPercent: Int
    public var windowDurationMinutes: Int

    public init(remainingPercent: Int, windowDurationMinutes: Int) {
        self.remainingPercent = remainingPercent
        self.windowDurationMinutes = windowDurationMinutes
    }

    fileprivate var compactSummary: String {
        let duration: String
        if windowDurationMinutes >= 24 * 60, windowDurationMinutes.isMultiple(of: 24 * 60) {
            duration = "\(windowDurationMinutes / (24 * 60))d"
        } else if windowDurationMinutes >= 60, windowDurationMinutes.isMultiple(of: 60) {
            duration = "\(windowDurationMinutes / 60)h"
        } else {
            duration = "\(windowDurationMinutes)m"
        }
        return "\(duration) \(min(100, max(0, remainingPercent)))%"
    }
}

// CodexUsageSnapshot 是 Go 已缓存的用量事实，Swift 不直接查询 Codex。
public struct CodexUsageSnapshot: Codable, Equatable {
    public var status: CodexUsageStatus
    public var primary: CodexUsageWindow?

    public init(status: CodexUsageStatus = .loading, primary: CodexUsageWindow? = nil) {
        self.status = status
        self.primary = primary
    }

    public var compactSummary: String {
        switch status {
        case .loading:
            return "…"
        case .unavailable:
            return "—"
        case .available:
            return primary?.compactSummary ?? "—"
        }
    }
}

public enum CodexActivityStatus: String, Codable, Equatable {
    case loading
    case available
    case unavailable
}

// CodexCompletionEvent 使用 Codex turn ID 作为跨轮询稳定身份。
public struct CodexCompletionEvent: Codable, Equatable {
    public var id: String
    public var threadId: String
    public var title: String
    public var completedAt: Int64

    public init(id: String, threadId: String, title: String, completedAt: Int64) {
        self.id = id
        self.threadId = threadId
        self.title = title
        self.completedAt = completedAt
    }
}

// CodexActivitySnapshot 表示任务监控可用状态与最近一次完成事实。
public struct CodexActivitySnapshot: Codable, Equatable {
    public var status: CodexActivityStatus
    public var completionEvent: CodexCompletionEvent?
    public var message: String?

    public init(
        status: CodexActivityStatus = .loading,
        completionEvent: CodexCompletionEvent? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.completionEvent = completionEvent
        self.message = message
    }
}

// SurfaceState 是协议 v5 的完整只读组合快照。
public struct SurfaceState: Codable, Equatable {
    public var revision: UInt64
    public var codex: CodexUsageSnapshot
    public var activity: CodexActivitySnapshot

    public init(
        revision: UInt64 = 0,
        codex: CodexUsageSnapshot = CodexUsageSnapshot(),
        activity: CodexActivitySnapshot = CodexActivitySnapshot()
    ) {
        self.revision = revision
        self.codex = codex
        self.activity = activity
    }
}
