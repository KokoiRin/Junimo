import Foundation

public protocol ActionCore {
    func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult
}

public protocol PomodoroCore {
    func start(duration: TimeInterval, at date: Date)
    func cancel(at date: Date) -> CppPomodoroResult
    func advanceTime(to date: Date) -> CppPomodoroResult
}

public protocol CommandCatalogCore {
    func searchCommands(query: String) -> [CommandPaletteEntry]
    func projectProfile() -> ProjectProfileSummary
}

public protocol SessionTimelineCore {
    func recentSessions() -> [ExecutionSessionSummary]
}

public protocol PreferencesCore {
    func uiPreferences() -> ConsolePreferences
    func setAccent(_ accent: ConsoleAccent) -> ConsolePreferences
    func setDensity(_ density: ConsoleDensity) -> ConsolePreferences
}

public protocol ConsoleStateCore {
    func agents() -> [AgentSummary]
    func actions() -> [ConsoleAction]
    func recentActivities() -> [ActivityEntry]
    func activePomodoro() -> PomodoroSession?
    func recordActivity(title: String, detail: String, at date: Date)
}

public protocol CornerNoteCore {
    func cornerNote() -> CornerNoteSnapshot
    func updateCornerNoteText(_ text: String) -> CornerNoteSnapshot
    func addCornerTodo(title: String) -> CornerNoteSnapshot
    func updateCornerTodo(id: UUID, title: String) -> CornerNoteSnapshot
    func toggleCornerTodo(id: UUID) -> CornerNoteSnapshot
    func removeCornerTodo(id: UUID) -> CornerNoteSnapshot
}

public final class CppBackedCore: ActionCore, PomodoroCore, CommandCatalogCore, SessionTimelineCore, PreferencesCore, ConsoleStateCore, CornerNoteCore {
    private let engine: CppCoreEngine

    public init?() {
        guard let engine = CppCoreEngine() else {
            return nil
        }
        self.engine = engine
    }

    public func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult {
        let result = engine.runAction(id: action.id, at: date)
        guard result.handled else {
            return TaskExecutionResult(title: "\(action.title) ignored", detail: "C++ core did not handle this action")
        }

        return TaskExecutionResult(
            title: result.activityTitle,
            detail: result.activityDetail,
            agentID: result.agentID,
            agentStatus: result.agentStatus
        )
    }

    public func agents() -> [AgentSummary] {
        engine.agents()
    }

    public func actions() -> [ConsoleAction] {
        engine.actions()
    }

    public func recentActivities() -> [ActivityEntry] {
        engine.recentActivities()
    }

    public func activePomodoro() -> PomodoroSession? {
        engine.activePomodoro()
    }

    public func recordActivity(title: String, detail: String, at date: Date) {
        engine.recordActivity(title: title, detail: detail, at: date)
    }

    public func start(duration: TimeInterval, at date: Date) {
        engine.startPomodoro(duration: duration, at: date)
    }

    public func cancel(at date: Date) -> CppPomodoroResult {
        engine.cancelPomodoro(at: date)
    }

    public func advanceTime(to date: Date) -> CppPomodoroResult {
        engine.advanceTime(to: date)
    }

    public func searchCommands(query: String) -> [CommandPaletteEntry] {
        engine.searchCommands(query: query)
    }

    public func projectProfile() -> ProjectProfileSummary {
        engine.projectProfile()
    }

    public func recentSessions() -> [ExecutionSessionSummary] {
        engine.recentSessions()
    }

    public func uiPreferences() -> ConsolePreferences {
        engine.uiPreferences()
    }

    public func setAccent(_ accent: ConsoleAccent) -> ConsolePreferences {
        engine.setAccent(accent)
    }

    public func setDensity(_ density: ConsoleDensity) -> ConsolePreferences {
        engine.setDensity(density)
    }

    public func cornerNote() -> CornerNoteSnapshot {
        engine.cornerNote()
    }

    public func updateCornerNoteText(_ text: String) -> CornerNoteSnapshot {
        engine.updateCornerNoteText(text)
    }

    public func addCornerTodo(title: String) -> CornerNoteSnapshot {
        engine.addCornerTodo(title: title)
    }

    public func updateCornerTodo(id: UUID, title: String) -> CornerNoteSnapshot {
        engine.updateCornerTodo(id: id, title: title)
    }

    public func toggleCornerTodo(id: UUID) -> CornerNoteSnapshot {
        engine.toggleCornerTodo(id: id)
    }

    public func removeCornerTodo(id: UUID) -> CornerNoteSnapshot {
        engine.removeCornerTodo(id: id)
    }
}

public final class SwiftFallbackCore: ActionCore, PomodoroCore, CommandCatalogCore, SessionTimelineCore, PreferencesCore, ConsoleStateCore, CornerNoteCore {
    private var preferences = ConsolePreferences()
    private var hasActivePomodoro = false
    private var agentsValue = [
        AgentSummary(id: "codex", name: "Codex", status: .idle, detail: "Ready for local coding tasks"),
        AgentSummary(id: "hermes", name: "Hermes", status: .idle, detail: "Ready for orchestration")
    ]
    private var actionsValue = [
        ConsoleAction(id: "codex", title: "Codex", subtitle: "Start local coding agent", kind: .agent, agentID: "codex"),
        ConsoleAction(id: "hermes", title: "Hermes", subtitle: "Start mock orchestration", kind: .agent, agentID: "hermes"),
        ConsoleAction(id: "open-project", title: "Project", subtitle: "Queue project shortcut", kind: .project),
        ConsoleAction(id: "dev-tools", title: "Tools", subtitle: "Queue developer tools", kind: .tool)
    ]
    private var activitiesValue = [
        ActivityEntry(title: "Junimo started", detail: "Hover the capsule to open the console", date: Date())
    ]
    private var pomodoroValue: PomodoroSession?
    private var cornerNoteSnapshot = CornerNoteSnapshot(
        text: "Quick note",
        todos: [
            CornerTodoItem(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "Capture an idea"),
            CornerTodoItem(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, title: "Turn it into a task")
        ]
    )

    public init() {}

    public func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult {
        let result = MockTaskExecutionAdapter().run(action: action, at: date)
        if let agentID = result.agentID, let status = result.agentStatus,
           let index = agentsValue.firstIndex(where: { $0.id == agentID }) {
            agentsValue[index].status = status
            agentsValue[index].detail = result.detail
        }
        activitiesValue.insert(ActivityEntry(title: result.title, detail: result.detail, date: date), at: 0)
        activitiesValue = Array(activitiesValue.prefix(8))
        return result
    }

    public func start(duration: TimeInterval, at date: Date) {
        hasActivePomodoro = true
        pomodoroValue = PomodoroSession(startedAt: date, duration: duration)
        activitiesValue.insert(ActivityEntry(title: "Pomodoro started", detail: "Focus session created in fallback core", date: date), at: 0)
        activitiesValue = Array(activitiesValue.prefix(8))
    }

    public func cancel(at date: Date) -> CppPomodoroResult {
        guard hasActivePomodoro else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        hasActivePomodoro = false
        pomodoroValue = nil
        activitiesValue.insert(ActivityEntry(title: "Pomodoro cancelled", detail: "Focus session stopped", date: date), at: 0)
        activitiesValue = Array(activitiesValue.prefix(8))
        return CppPomodoroResult(
            changed: true,
            completed: false,
            activityTitle: "Pomodoro cancelled",
            activityDetail: "Focus session stopped",
            notificationTitle: "",
            notificationBody: ""
        )
    }

    public func advanceTime(to date: Date) -> CppPomodoroResult {
        guard hasActivePomodoro else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        hasActivePomodoro = false
        pomodoroValue = nil
        activitiesValue.insert(ActivityEntry(title: "Pomodoro complete", detail: "Reminder is ready", date: date), at: 0)
        activitiesValue = Array(activitiesValue.prefix(8))
        return CppPomodoroResult(
            changed: true,
            completed: true,
            activityTitle: "Pomodoro complete",
            activityDetail: "Reminder is ready",
            notificationTitle: "Pomodoro complete",
            notificationBody: "Focus session finished."
        )
    }

    public func searchCommands(query: String) -> [CommandPaletteEntry] {
        let entries = [
            CommandPaletteEntry(id: "codex", title: "Start Codex", subtitle: "Queue the local coding agent", category: "Agents"),
            CommandPaletteEntry(id: "hermes", title: "Start Hermes", subtitle: "Queue orchestration workflow", category: "Agents"),
            CommandPaletteEntry(id: "open-project", title: "Open Project", subtitle: "Focus the current Junimo workspace", category: "Project"),
            CommandPaletteEntry(id: "dev-tools", title: "Developer Tools", subtitle: "Queue local development utilities", category: "Tools")
        ]
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query) ||
            entry.subtitle.localizedCaseInsensitiveContains(query) ||
            entry.category.localizedCaseInsensitiveContains(query)
        }
    }

    public func projectProfile() -> ProjectProfileSummary {
        ProjectProfileSummary(
            name: "Junimo",
            path: "/Users/guoysh/Documents/Junimo",
            stack: "Swift/AppKit shell + C++23 core",
            shortcuts: ["Build app", "Run tests", "OpenSpec validate"]
        )
    }

    public func recentSessions() -> [ExecutionSessionSummary] {
        []
    }

    public func agents() -> [AgentSummary] {
        agentsValue
    }

    public func actions() -> [ConsoleAction] {
        actionsValue
    }

    public func recentActivities() -> [ActivityEntry] {
        activitiesValue
    }

    public func activePomodoro() -> PomodoroSession? {
        pomodoroValue
    }

    public func recordActivity(title: String, detail: String, at date: Date) {
        activitiesValue.insert(ActivityEntry(title: title, detail: detail, date: date), at: 0)
        activitiesValue = Array(activitiesValue.prefix(8))
    }

    public func uiPreferences() -> ConsolePreferences {
        preferences
    }

    public func setAccent(_ accent: ConsoleAccent) -> ConsolePreferences {
        preferences.accent = accent
        return preferences
    }

    public func setDensity(_ density: ConsoleDensity) -> ConsolePreferences {
        preferences.density = density
        switch density {
        case .comfortable:
            preferences.expandedWidth = 760
            preferences.expandedHeight = 300
        case .compact:
            preferences.expandedWidth = 700
            preferences.expandedHeight = 470
        }
        return preferences
    }

    public func cornerNote() -> CornerNoteSnapshot {
        cornerNoteSnapshot
    }

    public func updateCornerNoteText(_ text: String) -> CornerNoteSnapshot {
        cornerNoteSnapshot.text = text
        return cornerNoteSnapshot
    }

    public func addCornerTodo(title: String) -> CornerNoteSnapshot {
        cornerNoteSnapshot.todos.append(CornerTodoItem(title: title))
        return cornerNoteSnapshot
    }

    public func updateCornerTodo(id: UUID, title: String) -> CornerNoteSnapshot {
        guard let index = cornerNoteSnapshot.todos.firstIndex(where: { $0.id == id }) else {
            return cornerNoteSnapshot
        }
        cornerNoteSnapshot.todos[index].title = title
        return cornerNoteSnapshot
    }

    public func toggleCornerTodo(id: UUID) -> CornerNoteSnapshot {
        guard let index = cornerNoteSnapshot.todos.firstIndex(where: { $0.id == id }) else {
            return cornerNoteSnapshot
        }
        cornerNoteSnapshot.todos[index].isDone.toggle()
        return cornerNoteSnapshot
    }

    public func removeCornerTodo(id: UUID) -> CornerNoteSnapshot {
        cornerNoteSnapshot.todos.removeAll { $0.id == id }
        return cornerNoteSnapshot
    }
}
