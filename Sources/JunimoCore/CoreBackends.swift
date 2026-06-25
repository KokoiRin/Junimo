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

public final class CppBackedCore: ActionCore, PomodoroCore, CommandCatalogCore, SessionTimelineCore, PreferencesCore {
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
}

public final class SwiftFallbackCore: ActionCore, PomodoroCore, CommandCatalogCore, SessionTimelineCore, PreferencesCore {
    private var preferences = ConsolePreferences()
    private var hasActivePomodoro = false

    public init() {}

    public func run(action: ConsoleAction, at date: Date) -> TaskExecutionResult {
        MockTaskExecutionAdapter().run(action: action, at: date)
    }

    public func start(duration: TimeInterval, at date: Date) {
        hasActivePomodoro = true
    }

    public func cancel(at date: Date) -> CppPomodoroResult {
        guard hasActivePomodoro else {
            return CppPomodoroResult(changed: false, completed: false, activityTitle: "", activityDetail: "", notificationTitle: "", notificationBody: "")
        }
        hasActivePomodoro = false
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
            preferences.expandedHeight = 220
        case .compact:
            preferences.expandedWidth = 700
            preferences.expandedHeight = 470
        }
        return preferences
    }
}
