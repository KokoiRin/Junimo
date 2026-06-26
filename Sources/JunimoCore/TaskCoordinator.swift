import Combine
import Foundation

/// Coordinates console intent between UI state and the native core.
/// SwiftUI views call this type for user intent; C++23 core/adapter boundaries
/// produce domain results. It avoids AppKit window ownership and shell work.
public final class TaskCoordinator: ObservableObject {
    @Published public private(set) var isExpanded: Bool = false {
        didSet {
            if oldValue != isExpanded {
                expansionDidChange?(isExpanded)
            }
        }
    }

    @Published public private(set) var agents: [AgentSummary]
    @Published public private(set) var actions: [ConsoleAction]
    @Published public private(set) var recentActivities: [ActivityEntry]
    @Published public private(set) var commandQuery: String
    @Published public private(set) var commandResults: [CommandPaletteEntry]
    @Published public private(set) var projectProfile: ProjectProfileSummary
    @Published public private(set) var sessions: [ExecutionSessionSummary]
    @Published public private(set) var codexMonitor: CodexMonitorSnapshot
    @Published public private(set) var preferences: ConsolePreferences
    @Published public var theme: ConsoleTheme
    @Published public private(set) var activePomodoro: PomodoroSession?
    @Published public private(set) var pendingNotifications: [NotificationRequest]
    @Published public private(set) var isCornerNoteExpanded: Bool = false {
        didSet {
            if oldValue != isCornerNoteExpanded {
                cornerNoteExpansionDidChange?(isCornerNoteExpanded)
            }
        }
    }
    @Published public private(set) var cornerNoteText: String
    @Published public private(set) var cornerTodos: [CornerTodoItem]

    public var expansionDidChange: ((Bool) -> Void)?
    public var layoutPreferencesDidChange: ((ConsolePreferences) -> Void)?
    public var cornerNoteExpansionDidChange: ((Bool) -> Void)?

    private let actionCore: ActionCore
    private let pomodoroCore: PomodoroCore
    private let commandCatalogCore: CommandCatalogCore
    private let sessionTimelineCore: SessionTimelineCore
    private let preferencesCore: PreferencesCore
    private let consoleStateCore: ConsoleStateCore
    private let cornerNoteCore: CornerNoteCore
    private var nowProvider: () -> Date

    public init(
        core: (ActionCore & PomodoroCore & CommandCatalogCore & SessionTimelineCore & PreferencesCore & ConsoleStateCore & CornerNoteCore)? = CppBackedCore(),
        now: Date = Date(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedCore = core ?? SwiftFallbackCore()
        self.actionCore = resolvedCore
        self.pomodoroCore = resolvedCore
        self.commandCatalogCore = resolvedCore
        self.sessionTimelineCore = resolvedCore
        self.preferencesCore = resolvedCore
        self.consoleStateCore = resolvedCore
        self.cornerNoteCore = resolvedCore
        self.nowProvider = nowProvider
        let cornerNoteSnapshot = resolvedCore.cornerNote()
        self.agents = resolvedCore.agents()
        self.actions = resolvedCore.actions()
        self.recentActivities = resolvedCore.recentActivities()
        self.commandQuery = ""
        self.commandResults = resolvedCore.searchCommands(query: "")
        self.projectProfile = resolvedCore.projectProfile()
        self.sessions = resolvedCore.recentSessions()
        self.codexMonitor = CodexMonitorSnapshot.researchedDefault(now: now)
        let resolvedPreferences = resolvedCore.uiPreferences()
        self.preferences = resolvedPreferences
        self.theme = ConsoleTheme(accent: resolvedPreferences.accent)
        self.activePomodoro = resolvedCore.activePomodoro()
        self.pendingNotifications = []
        self.cornerNoteText = cornerNoteSnapshot.text
        self.cornerTodos = cornerNoteSnapshot.todos
    }

    public func pointerEntered(at date: Date? = nil) {
        isExpanded = true
    }

    public func pointerExited(at date: Date? = nil) {
        isExpanded = false
    }

    public func advanceTime(to date: Date) {
        completePomodoroIfNeeded(now: date)
    }

    public func performAction(id: String, now: Date? = nil) {
        guard let action = actions.first(where: { $0.id == id }) else {
            return
        }

        let date = now ?? nowProvider()
        let result = actionCore.run(action: action, at: date)
        refreshConsoleState()
        if action.id == "codex" {
            updateCodexThread(
                id: "junimo-local-codex",
                title: "Junimo Codex",
                status: .running,
                detail: result.detail,
                now: date
            )
        }
    }

    public func performCommand(id: String, now: Date? = nil) {
        switch id {
        case "pomodoro-25":
            startPomodoro(duration: 25 * 60, now: now)
        case "pomodoro-10s":
            startPomodoro(duration: 10, now: now)
        default:
            performAction(id: id, now: now)
        }
    }

    public func setAccent(_ accent: ConsoleAccent) {
        let updated = preferencesCore.setAccent(accent)
        preferences = updated
        theme.accent = updated.accent
        layoutPreferencesDidChange?(updated)
    }

    public func setDensity(_ density: ConsoleDensity) {
        let updated = preferencesCore.setDensity(density)
        preferences = updated
        theme.accent = updated.accent
        layoutPreferencesDidChange?(updated)
    }

    public func updateCommandQuery(_ query: String) {
        commandQuery = query
        commandResults = commandCatalogCore.searchCommands(query: query)
    }

    public func startPomodoro(duration: TimeInterval = 25 * 60, now: Date? = nil) {
        let date = now ?? nowProvider()
        pomodoroCore.start(duration: duration, at: date)
        refreshConsoleState()
    }

    public func cancelPomodoro(now: Date? = nil) {
        let date = now ?? nowProvider()
        let result = pomodoroCore.cancel(at: date)
        if result.changed {
            refreshConsoleState()
        }
    }

    public func markNotificationDelivered(id: UUID) {
        pendingNotifications.removeAll { $0.id == id }
    }

    public func setCornerNoteExpanded(_ isExpanded: Bool) {
        isCornerNoteExpanded = isExpanded
    }

    public func updateCornerNoteText(_ text: String) {
        applyCornerNoteSnapshot(cornerNoteCore.updateCornerNoteText(text))
    }

    public func addCornerTodo(title: String = "") {
        applyCornerNoteSnapshot(cornerNoteCore.addCornerTodo(title: title))
    }

    public func updateCornerTodo(id: UUID, title: String) {
        applyCornerNoteSnapshot(cornerNoteCore.updateCornerTodo(id: id, title: title))
    }

    public func toggleCornerTodo(id: UUID) {
        applyCornerNoteSnapshot(cornerNoteCore.toggleCornerTodo(id: id))
    }

    public func removeCornerTodo(id: UUID) {
        applyCornerNoteSnapshot(cornerNoteCore.removeCornerTodo(id: id))
    }

    public func refreshCodexMonitor(_ snapshot: CodexMonitorSnapshot, now: Date? = nil) {
        let date = now ?? nowProvider()
        let incomingThreadIDs = Set(snapshot.threads.map(\.id))
        let missingActiveThreads = codexMonitor.threads.filter { thread in
            thread.status.isActive && !incomingThreadIDs.contains(thread.id)
        }

        codexMonitor.usage = snapshot.usage
        codexMonitor.findings = snapshot.findings
        codexMonitor.refreshedAt = snapshot.refreshedAt
        codexMonitor.threads.removeAll { thread in
            !thread.status.isActive && !incomingThreadIDs.contains(thread.id)
        }

        for thread in snapshot.threads {
            updateCodexThread(
                id: thread.id,
                title: thread.title,
                status: thread.status,
                detail: thread.detail,
                now: thread.updatedAt
            )
        }

        for thread in missingActiveThreads {
            updateCodexThread(
                id: thread.id,
                title: thread.title,
                status: .completed,
                detail: "Thread no longer appears in the latest Codex snapshot",
                now: date
            )
        }

        refreshCodexAgentStatus(now: date)
    }

    public func updateCodexThread(id: String, title: String, status: CodexThreadStatus, detail: String, now: Date? = nil) {
        let date = now ?? nowProvider()
        let previousStatus = codexMonitor.threads.first(where: { $0.id == id })?.status
        let updatedThread = CodexThreadSummary(id: id, title: title, status: status, detail: detail, updatedAt: date)

        if let index = codexMonitor.threads.firstIndex(where: { $0.id == id }) {
            codexMonitor.threads[index] = updatedThread
        } else {
            codexMonitor.threads.insert(updatedThread, at: 0)
        }

        codexMonitor.threads.sort { $0.updatedAt > $1.updatedAt }
        if codexMonitor.threads.count > 8 {
            codexMonitor.threads.removeLast(codexMonitor.threads.count - 8)
        }

        if previousStatus?.isActive == true && !status.isActive {
            let notification = NotificationRequest(
                title: status == .failed ? "Codex thread failed" : "Codex thread complete",
                body: "\(title): \(detail)",
                createdAt: date
            )
            pendingNotifications.append(notification)
            recordActivity(
                title: notification.title,
                detail: notification.body,
                date: date
            )
        }

        refreshCodexAgentStatus(now: date)
    }

    private func completePomodoroIfNeeded(now: Date) {
        let result = pomodoroCore.advanceTime(to: now)
        guard result.completed else {
            return
        }
        let notification = NotificationRequest(
            title: result.notificationTitle,
            body: result.notificationBody,
            createdAt: now
        )
        pendingNotifications.append(notification)
        refreshConsoleState()
    }

    private func updateAgent(id: String, status: AgentStatus, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else {
            return
        }
        agents[index].status = status
        agents[index].detail = detail
    }

    private func refreshCodexAgentStatus(now: Date) {
        let activeCount = codexMonitor.activeThreadCount
        if activeCount > 0 {
            updateAgent(
                id: "codex",
                status: .running,
                detail: "\(activeCount) Codex thread\(activeCount == 1 ? "" : "s") active"
            )
            return
        }

        if let latest = codexMonitor.latestThread {
            let agentStatus: AgentStatus = latest.status == .failed ? .failed : .succeeded
            updateAgent(id: "codex", status: agentStatus, detail: latest.detail)
            return
        }

        updateAgent(id: "codex", status: .idle, detail: codexMonitor.usage.detail)
    }

    private func recordActivity(title: String, detail: String, date: Date) {
        consoleStateCore.recordActivity(title: title, detail: detail, at: date)
        recentActivities = consoleStateCore.recentActivities()
    }

    private func refreshSessions() {
        sessions = sessionTimelineCore.recentSessions()
    }

    private func refreshConsoleState() {
        agents = consoleStateCore.agents()
        actions = consoleStateCore.actions()
        recentActivities = consoleStateCore.recentActivities()
        activePomodoro = consoleStateCore.activePomodoro()
        refreshSessions()
    }

    private func applyCornerNoteSnapshot(_ snapshot: CornerNoteSnapshot) {
        cornerNoteText = snapshot.text
        cornerTodos = snapshot.todos
    }
}
