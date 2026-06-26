import Combine
import Foundation

/// Core state models for the Junimo console.
/// This module owns user-visible state and adapter contracts, but does not own
/// AppKit windows, SwiftUI layout, shell execution, or real agent protocols.
public enum AgentStatus: String, CaseIterable, Equatable {
    case idle
    case running
    case succeeded
    case failed

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .succeeded: "Ready"
        case .failed: "Needs attention"
        }
    }
}

public struct AgentSummary: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var status: AgentStatus
    public var detail: String

    public init(id: String, name: String, status: AgentStatus, detail: String) {
        self.id = id
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public enum ConsoleActionKind: String, Equatable {
    case agent
    case tool
    case project
}

public struct ConsoleAction: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var kind: ConsoleActionKind
    public var agentID: String?

    public init(id: String, title: String, subtitle: String, kind: ConsoleActionKind, agentID: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.agentID = agentID
    }
}

public struct ActivityEntry: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var date: Date

    public init(id: UUID = UUID(), title: String, detail: String, date: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.date = date
    }
}

public enum ConsoleAccent: String, CaseIterable, Identifiable, Equatable {
    case mint
    case amber
    case graphite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mint: "Mint"
        case .amber: "Amber"
        case .graphite: "Graphite"
        }
    }
}

public struct ConsoleTheme: Equatable {
    public var accent: ConsoleAccent

    public init(accent: ConsoleAccent = .mint) {
        self.accent = accent
    }
}

public enum ConsoleDensity: String, CaseIterable, Identifiable, Equatable {
    case comfortable
    case compact

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .comfortable: "Comfort"
        case .compact: "Compact"
        }
    }
}

public struct ConsolePreferences: Equatable {
    public var accent: ConsoleAccent
    public var density: ConsoleDensity
    public var expandedWidth: Int
    public var expandedHeight: Int
    public var topOffset: Int

    public init(
        accent: ConsoleAccent = .mint,
        density: ConsoleDensity = .comfortable,
        expandedWidth: Int = 760,
        expandedHeight: Int = 300,
        topOffset: Int = 6
    ) {
        self.accent = accent
        self.density = density
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.topOffset = topOffset
    }
}

public struct TaskExecutionResult: Equatable {
    public var title: String
    public var detail: String
    public var agentID: String?
    public var agentStatus: AgentStatus?

    public init(title: String, detail: String, agentID: String? = nil, agentStatus: AgentStatus? = nil) {
        self.title = title
        self.detail = detail
        self.agentID = agentID
        self.agentStatus = agentStatus
    }
}

public protocol TaskExecutionAdapter {
    func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult
}

public struct MockTaskExecutionAdapter: TaskExecutionAdapter {
    public init() {}

    public func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult {
        switch action.id {
        case "codex":
            TaskExecutionResult(
                title: "Started Codex",
                detail: "Mock Codex agent queued through TaskCoordinator",
                agentID: action.agentID,
                agentStatus: .running
            )
        case "hermes":
            TaskExecutionResult(
                title: "Started Hermes",
                detail: "Mock Hermes orchestration started",
                agentID: action.agentID,
                agentStatus: .running
            )
        case "open-project":
            TaskExecutionResult(
                title: "Project action queued",
                detail: "Open current project placeholder was routed through adapter"
            )
        default:
            TaskExecutionResult(
                title: "\(action.title) queued",
                detail: "Mock action was routed through adapter"
            )
        }
    }
}

public struct PomodoroSession: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var startedAt: Date
    public var duration: TimeInterval

    public init(id: UUID = UUID(), title: String = "Focus", startedAt: Date, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
    }

    public var endsAt: Date {
        startedAt.addingTimeInterval(duration)
    }

    public func remaining(at date: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(date))
    }

    public func isComplete(at date: Date) -> Bool {
        date >= endsAt
    }
}

public struct NotificationRequest: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, createdAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

public struct CornerTodoItem: Identifiable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct CornerNoteSnapshot: Equatable {
    public var text: String
    public var todos: [CornerTodoItem]

    public init(text: String, todos: [CornerTodoItem]) {
        self.text = text
        self.todos = todos
    }
}

public enum CodexCapabilityStatus: String, Equatable {
    case available
    case needsSetup
    case unsupported
    case degraded

    public var label: String {
        switch self {
        case .available: "Available"
        case .needsSetup: "Needs setup"
        case .unsupported: "Unsupported"
        case .degraded: "Degraded"
        }
    }
}

public struct CodexUsageWindow: Equatable {
    public var label: String
    public var usedPercent: Int?
    public var resetsAt: Date?
    public var durationMinutes: Int?

    public init(label: String, usedPercent: Int? = nil, resetsAt: Date? = nil, durationMinutes: Int? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }
}

public struct CodexUsageSnapshot: Equatable {
    public var status: CodexCapabilityStatus
    public var planLabel: String
    public var detail: String
    public var source: String
    public var primaryWindow: CodexUsageWindow?
    public var secondaryWindow: CodexUsageWindow?
    public var creditsBalance: String?

    public init(
        status: CodexCapabilityStatus,
        planLabel: String,
        detail: String,
        source: String,
        primaryWindow: CodexUsageWindow? = nil,
        secondaryWindow: CodexUsageWindow? = nil,
        creditsBalance: String? = nil
    ) {
        self.status = status
        self.planLabel = planLabel
        self.detail = detail
        self.source = source
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.creditsBalance = creditsBalance
    }

    public var summaryText: String {
        if let primaryWindow, let usedPercent = primaryWindow.usedPercent {
            return "\(max(0, 100 - usedPercent))% left"
        }
        return status.label
    }
}

public enum CodexThreadStatus: String, Equatable {
    case idle
    case running
    case waiting
    case completed
    case failed

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .waiting: "Waiting"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    public var isActive: Bool {
        self == .running || self == .waiting
    }
}

public struct CodexThreadSummary: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var status: CodexThreadStatus
    public var detail: String
    public var updatedAt: Date

    public init(id: String, title: String, status: CodexThreadStatus, detail: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct CodexIntegrationFinding: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var status: CodexCapabilityStatus
    public var detail: String

    public init(id: String, title: String, status: CodexCapabilityStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct CodexMonitorSnapshot: Equatable {
    public var usage: CodexUsageSnapshot
    public var threads: [CodexThreadSummary]
    public var findings: [CodexIntegrationFinding]
    public var refreshedAt: Date

    public init(
        usage: CodexUsageSnapshot,
        threads: [CodexThreadSummary],
        findings: [CodexIntegrationFinding],
        refreshedAt: Date
    ) {
        self.usage = usage
        self.threads = threads
        self.findings = findings
        self.refreshedAt = refreshedAt
    }

    public var activeThreadCount: Int {
        threads.filter { $0.status.isActive }.count
    }

    public var latestThread: CodexThreadSummary? {
        threads.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    public static func researchedDefault(now: Date) -> CodexMonitorSnapshot {
        CodexMonitorSnapshot(
            usage: CodexUsageSnapshot(
                status: .needsSetup,
                planLabel: "Codex quota",
                detail: "Use Codex app-server account/rateLimits/read for live rate-limit windows.",
                source: "Codex app-server"
            ),
            threads: [],
            findings: [
                CodexIntegrationFinding(
                    id: "app-server",
                    title: "Live local threads",
                    status: .needsSetup,
                    detail: "Connect to codex app-server, then call thread/list and listen for turn/thread notifications."
                ),
                CodexIntegrationFinding(
                    id: "exec-json",
                    title: "Junimo-launched runs",
                    status: .available,
                    detail: "codex exec --json emits turn.completed and turn.failed for completion alerts."
                ),
                CodexIntegrationFinding(
                    id: "cloud-list",
                    title: "Cloud tasks",
                    status: .available,
                    detail: "codex cloud list --json returns recent cloud task status when authenticated."
                ),
                CodexIntegrationFinding(
                    id: "analytics",
                    title: "Historical usage",
                    status: .degraded,
                    detail: "Enterprise Analytics reports daily/weekly usage, but may lag and is not a personal live quota meter."
                )
            ],
            refreshedAt: now
        )
    }
}

public struct CommandPaletteEntry: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var category: String

    public init(id: String, title: String, subtitle: String, category: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
    }
}

public struct ProjectProfileSummary: Equatable {
    public var name: String
    public var path: String
    public var stack: String
    public var shortcuts: [String]

    public init(name: String, path: String, stack: String, shortcuts: [String]) {
        self.name = name
        self.path = path
        self.stack = stack
        self.shortcuts = shortcuts
    }
}

public enum ExecutionSessionStatus: Int32, Equatable {
    case queued = 0
    case running = 1
    case succeeded = 2
    case failed = 3

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .succeeded: "Done"
        case .failed: "Failed"
        }
    }
}

public struct ExecutionSessionSummary: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var detail: String
    public var status: ExecutionSessionStatus
    public var statusLabel: String
    public var startedAt: Date

    public init(id: String, title: String, detail: String, status: ExecutionSessionStatus, statusLabel: String, startedAt: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.statusLabel = statusLabel
        self.startedAt = startedAt
    }
}
