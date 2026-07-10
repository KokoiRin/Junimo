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

public struct PomodoroSnapshot: Codable, Equatable {
    public var mode: PomodoroMode
    public var status: PomodoroStatus
    public var remainingSeconds: Int
    public var focusDurationSeconds: Int

    public init(
        mode: PomodoroMode = .focus,
        status: PomodoroStatus = .idle,
        remainingSeconds: Int = 25 * 60,
        focusDurationSeconds: Int = 25 * 60
    ) {
        self.mode = mode
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.focusDurationSeconds = focusDurationSeconds
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
    public var pomodoro: PomodoroSnapshot
    public var codex: CodexUsageSnapshot?

    public init(pomodoro: PomodoroSnapshot = PomodoroSnapshot(), codex: CodexUsageSnapshot? = nil) {
        self.pomodoro = pomodoro
        self.codex = codex
    }
}

public struct BackendIntent: Codable, Equatable {
    public var type: String
    public var durationSeconds: Int?

    public init(type: String, durationSeconds: Int? = nil) {
        self.type = type
        self.durationSeconds = durationSeconds
    }
}
