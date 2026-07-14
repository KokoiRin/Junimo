import Foundation

public enum PomodoroMode: String, Codable, Equatable {
    case focus
    case rest = "break"
}

public enum PomodoroStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case completed
}

// PomodoroCompletionEvent 表示 Go 状态机确认的一次完成事实，稳定 ID 供 macOS 外壳去重投递。
public struct PomodoroCompletionEvent: Codable, Equatable {
    public var id: UInt64
    public var mode: PomodoroMode

    public init(id: UInt64, mode: PomodoroMode) {
        self.id = id
        self.mode = mode
    }
}

public struct PomodoroSnapshot: Codable, Equatable {
    public var mode: PomodoroMode
    public var status: PomodoroStatus
    public var remainingSeconds: Int
    public var focusDurationSeconds: Int
    public var completionEvent: PomodoroCompletionEvent?

    public init(
        mode: PomodoroMode = .focus,
        status: PomodoroStatus = .idle,
        remainingSeconds: Int = 25 * 60,
        focusDurationSeconds: Int = 25 * 60,
        completionEvent: PomodoroCompletionEvent? = nil
    ) {
        self.mode = mode
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.focusDurationSeconds = focusDurationSeconds
        self.completionEvent = completionEvent
    }
}

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

public struct CodexUsageSnapshot: Codable, Equatable {
    public var status: CodexUsageStatus
    public var primary: CodexUsageWindow?

    public init(
        status: CodexUsageStatus = .loading,
        primary: CodexUsageWindow? = nil
    ) {
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
            guard let primary else { return "—" }
            return primary.compactSummary
        }
    }
}

public struct SurfaceState: Codable, Equatable {
    // revision 表示 Go 组合快照的单调时序，用于防止晚到响应回退界面状态。
    public var revision: UInt64
    public var pomodoro: PomodoroSnapshot
    public var codex: CodexUsageSnapshot?

    public init(
        revision: UInt64 = 0,
        pomodoro: PomodoroSnapshot = PomodoroSnapshot(),
        codex: CodexUsageSnapshot? = nil
    ) {
        self.revision = revision
        self.pomodoro = pomodoro
        self.codex = codex
    }
}

// PomodoroIntent 表示 Swift 外壳可发送的全部番茄钟用户意图，关联值固定每种动作的参数形状。
public enum PomodoroIntent: Equatable {
    case startFocus(durationSeconds: Int)
    case pause
    case resume
    case reset
    case startBreak
    case skipBreak
}
