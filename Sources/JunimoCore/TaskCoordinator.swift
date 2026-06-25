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
    @Published public private(set) var preferences: ConsolePreferences
    @Published public var theme: ConsoleTheme
    @Published public private(set) var activePomodoro: PomodoroSession?
    @Published public private(set) var pendingNotifications: [NotificationRequest]

    public var expansionDidChange: ((Bool) -> Void)?
    public var layoutPreferencesDidChange: ((ConsolePreferences) -> Void)?

    private let actionCore: ActionCore
    private let pomodoroCore: PomodoroCore
    private let commandCatalogCore: CommandCatalogCore
    private let sessionTimelineCore: SessionTimelineCore
    private let preferencesCore: PreferencesCore
    private var nowProvider: () -> Date

    public init(
        core: (ActionCore & PomodoroCore & CommandCatalogCore & SessionTimelineCore & PreferencesCore)? = CppBackedCore(),
        now: Date = Date(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedCore = core ?? SwiftFallbackCore()
        self.actionCore = resolvedCore
        self.pomodoroCore = resolvedCore
        self.commandCatalogCore = resolvedCore
        self.sessionTimelineCore = resolvedCore
        self.preferencesCore = resolvedCore
        self.nowProvider = nowProvider
        self.agents = [
            AgentSummary(id: "codex", name: "Codex", status: .idle, detail: "Ready for local coding tasks"),
            AgentSummary(id: "hermes", name: "Hermes", status: .idle, detail: "Ready for orchestration")
        ]
        self.actions = [
            ConsoleAction(id: "codex", title: "Codex", subtitle: "Start local coding agent", kind: .agent, agentID: "codex"),
            ConsoleAction(id: "hermes", title: "Hermes", subtitle: "Start mock orchestration", kind: .agent, agentID: "hermes"),
            ConsoleAction(id: "open-project", title: "Project", subtitle: "Queue project shortcut", kind: .project),
            ConsoleAction(id: "dev-tools", title: "Tools", subtitle: "Queue developer tools", kind: .tool)
        ]
        self.recentActivities = [
            ActivityEntry(title: "Junimo started", detail: "Hover the capsule to open the console", date: now)
        ]
        self.commandQuery = ""
        self.commandResults = resolvedCore.searchCommands(query: "")
        self.projectProfile = resolvedCore.projectProfile()
        self.sessions = resolvedCore.recentSessions()
        let resolvedPreferences = resolvedCore.uiPreferences()
        self.preferences = resolvedPreferences
        self.theme = ConsoleTheme(accent: resolvedPreferences.accent)
        self.pendingNotifications = []
    }

    public func pointerEntered(at date: Date? = nil) {
        isExpanded = true
    }

    public func pointerExited(at date: Date? = nil) {
        isExpanded = false
    }

    public func advanceTime(to date: Date) {
        if let session = activePomodoro, session.isComplete(at: date) {
            completePomodoro(session, now: date)
        }

    }

    public func performAction(id: String, now: Date? = nil) {
        guard let action = actions.first(where: { $0.id == id }) else {
            return
        }

        let date = now ?? nowProvider()
        let result = actionCore.run(action: action, at: date)
        if let agentID = result.agentID, let status = result.agentStatus {
            updateAgent(id: agentID, status: status, detail: result.detail)
        }
        recordActivity(title: result.title, detail: result.detail, date: date)
        refreshSessions()
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
        activePomodoro = PomodoroSession(startedAt: date, duration: duration)
        recordActivity(
            title: "Pomodoro started",
            detail: "Focus session created in C++ core",
            date: date
        )
        refreshSessions()
    }

    public func cancelPomodoro(now: Date? = nil) {
        guard activePomodoro != nil else {
            return
        }
        activePomodoro = nil
        let date = now ?? nowProvider()
        let result = pomodoroCore.cancel(at: date)
        if result.changed {
            recordActivity(title: result.activityTitle, detail: result.activityDetail, date: date)
            refreshSessions()
        }
    }

    public func markNotificationDelivered(id: UUID) {
        pendingNotifications.removeAll { $0.id == id }
    }

    private func completePomodoro(_ session: PomodoroSession, now: Date) {
        activePomodoro = nil
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
        recordActivity(title: result.activityTitle, detail: result.activityDetail, date: now)
        refreshSessions()
    }

    private func updateAgent(id: String, status: AgentStatus, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else {
            return
        }
        agents[index].status = status
        agents[index].detail = detail
    }

    private func recordActivity(title: String, detail: String, date: Date) {
        recentActivities.insert(ActivityEntry(title: title, detail: detail, date: date), at: 0)
        if recentActivities.count > 8 {
            recentActivities.removeLast(recentActivities.count - 8)
        }
    }

    private func refreshSessions() {
        sessions = sessionTimelineCore.recentSessions()
    }
}
