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

// TodoStatus 表示 Go Todo 领域已经确认的一条任务状态。
public enum TodoStatus: String, Codable, Equatable {
    case open
    case completed
}

// TodoAvailability 表示 Todo 事实源能否读取和接受写入。
public enum TodoAvailability: String, Codable, Equatable {
    case available
    case unavailable
}

// TodoItem 是 Swift 只读渲染的一条后端任务事实。
public struct TodoItem: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var status: TodoStatus

    // 初始化一条具有稳定后端身份的任务快照。
    public init(id: String, title: String, status: TodoStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

// TodoSnapshot 表示 Todo 页面渲染所需的完整后端事实。
public struct TodoSnapshot: Codable, Equatable {
    public var status: TodoAvailability
    public var items: [TodoItem]

    // 默认快照在旧协议数据缺少 Todo 时保持可渲染的空列表。
    public init(status: TodoAvailability = .available, items: [TodoItem] = []) {
        self.status = status
        self.items = items
    }
}

public struct SurfaceState: Codable, Equatable {
    // revision 表示 Go 组合快照的单调时序，用于防止晚到响应回退界面状态。
    public var revision: UInt64
    public var pomodoro: PomodoroSnapshot
    public var codex: CodexUsageSnapshot?
    public var todo: TodoSnapshot

    public init(
        revision: UInt64 = 0,
        pomodoro: PomodoroSnapshot = PomodoroSnapshot(),
        codex: CodexUsageSnapshot? = nil,
        todo: TodoSnapshot = TodoSnapshot()
    ) {
        self.revision = revision
        self.pomodoro = pomodoro
        self.codex = codex
        self.todo = todo
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case pomodoro
        case codex
        case todo
    }

    // 从组合快照解码；Todo 缺失只兼容旧录制数据，不改变协议版本检查。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(UInt64.self, forKey: .revision)
        pomodoro = try container.decode(PomodoroSnapshot.self, forKey: .pomodoro)
        codex = try container.decodeIfPresent(CodexUsageSnapshot.self, forKey: .codex)
        todo = try container.decodeIfPresent(TodoSnapshot.self, forKey: .todo) ?? TodoSnapshot()
    }

    // 编码完整组合快照，供 fake 与诊断工具保持同一数据形状。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encode(pomodoro, forKey: .pomodoro)
        try container.encodeIfPresent(codex, forKey: .codex)
        try container.encode(todo, forKey: .todo)
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

// TodoIntent 表示 Swift 外壳可发送的全部 Todo 用户意图，每种动作显式携带目标状态。
public enum TodoIntent: Equatable {
    case create(title: String)
    case rename(id: String, title: String)
    case setCompletion(id: String, completed: Bool)
    case delete(id: String)
}

// ProductIntent 统一 Swift 到 Go 的产品动作入口，同时保持各领域类型独立。
public enum ProductIntent: Equatable {
    case pomodoro(PomodoroIntent)
    case todo(TodoIntent)
}
