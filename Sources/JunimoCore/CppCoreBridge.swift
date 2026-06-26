import Foundation

typealias JunimoCoreEngineRef = OpaquePointer

struct JunimoCoreActionResultC {
    var handled: Int32
    var activityTitle: UnsafePointer<CChar>?
    var activityDetail: UnsafePointer<CChar>?
    var agentID: UnsafePointer<CChar>?
    var agentStatus: Int32
}

struct JunimoCorePomodoroResultC {
    var changed: Int32
    var completed: Int32
    var activityTitle: UnsafePointer<CChar>?
    var activityDetail: UnsafePointer<CChar>?
    var notificationTitle: UnsafePointer<CChar>?
    var notificationBody: UnsafePointer<CChar>?
}

struct JunimoCoreAgentSnapshotC {
    var id: UnsafePointer<CChar>?
    var name: UnsafePointer<CChar>?
    var detail: UnsafePointer<CChar>?
    var status: Int32
}

struct JunimoCoreAgentListC {
    var count: Int32
    var item0: JunimoCoreAgentSnapshotC
    var item1: JunimoCoreAgentSnapshotC
    var item2: JunimoCoreAgentSnapshotC
    var item3: JunimoCoreAgentSnapshotC
    var item4: JunimoCoreAgentSnapshotC
    var item5: JunimoCoreAgentSnapshotC
    var item6: JunimoCoreAgentSnapshotC
    var item7: JunimoCoreAgentSnapshotC
}

struct JunimoCoreActionSnapshotC {
    var id: UnsafePointer<CChar>?
    var title: UnsafePointer<CChar>?
    var subtitle: UnsafePointer<CChar>?
    var kind: Int32
    var agentID: UnsafePointer<CChar>?
}

struct JunimoCoreActionListC {
    var count: Int32
    var item0: JunimoCoreActionSnapshotC
    var item1: JunimoCoreActionSnapshotC
    var item2: JunimoCoreActionSnapshotC
    var item3: JunimoCoreActionSnapshotC
    var item4: JunimoCoreActionSnapshotC
    var item5: JunimoCoreActionSnapshotC
    var item6: JunimoCoreActionSnapshotC
    var item7: JunimoCoreActionSnapshotC
}

struct JunimoCoreActivitySnapshotC {
    var title: UnsafePointer<CChar>?
    var detail: UnsafePointer<CChar>?
    var createdAtUnixSeconds: Int64
}

struct JunimoCoreActivityListC {
    var count: Int32
    var item0: JunimoCoreActivitySnapshotC
    var item1: JunimoCoreActivitySnapshotC
    var item2: JunimoCoreActivitySnapshotC
    var item3: JunimoCoreActivitySnapshotC
    var item4: JunimoCoreActivitySnapshotC
    var item5: JunimoCoreActivitySnapshotC
    var item6: JunimoCoreActivitySnapshotC
    var item7: JunimoCoreActivitySnapshotC
}

struct JunimoCorePomodoroSnapshotC {
    var hasActive: Int32
    var title: UnsafePointer<CChar>?
    var startedAtUnixSeconds: Int64
    var durationSeconds: Int64
}

struct JunimoCoreCommandSnapshotC {
    var id: UnsafePointer<CChar>?
    var title: UnsafePointer<CChar>?
    var subtitle: UnsafePointer<CChar>?
    var category: UnsafePointer<CChar>?
}

struct JunimoCoreCommandListC {
    var count: Int32
    var item0: JunimoCoreCommandSnapshotC
    var item1: JunimoCoreCommandSnapshotC
    var item2: JunimoCoreCommandSnapshotC
    var item3: JunimoCoreCommandSnapshotC
    var item4: JunimoCoreCommandSnapshotC
    var item5: JunimoCoreCommandSnapshotC
    var item6: JunimoCoreCommandSnapshotC
    var item7: JunimoCoreCommandSnapshotC
}

struct JunimoCoreProjectProfileSnapshotC {
    var name: UnsafePointer<CChar>?
    var path: UnsafePointer<CChar>?
    var stack: UnsafePointer<CChar>?
    var shortcut1: UnsafePointer<CChar>?
    var shortcut2: UnsafePointer<CChar>?
    var shortcut3: UnsafePointer<CChar>?
}

struct JunimoCoreSessionSnapshotC {
    var id: UnsafePointer<CChar>?
    var title: UnsafePointer<CChar>?
    var detail: UnsafePointer<CChar>?
    var statusLabel: UnsafePointer<CChar>?
    var status: Int32
    var startedAtUnixSeconds: Int64
}

struct JunimoCoreSessionListC {
    var count: Int32
    var item0: JunimoCoreSessionSnapshotC
    var item1: JunimoCoreSessionSnapshotC
    var item2: JunimoCoreSessionSnapshotC
    var item3: JunimoCoreSessionSnapshotC
    var item4: JunimoCoreSessionSnapshotC
    var item5: JunimoCoreSessionSnapshotC
}

struct JunimoCoreUiPreferencesSnapshotC {
    var accent: UnsafePointer<CChar>?
    var density: UnsafePointer<CChar>?
    var expandedWidth: Int32
    var expandedHeight: Int32
    var topOffset: Int32
}

struct JunimoCoreCornerTodoSnapshotC {
    var id: UnsafePointer<CChar>?
    var title: UnsafePointer<CChar>?
    var isDone: Int32
}

struct JunimoCoreCornerNoteSnapshotC {
    var text: UnsafePointer<CChar>?
    var todoCount: Int32
    var item0: JunimoCoreCornerTodoSnapshotC
    var item1: JunimoCoreCornerTodoSnapshotC
    var item2: JunimoCoreCornerTodoSnapshotC
    var item3: JunimoCoreCornerTodoSnapshotC
    var item4: JunimoCoreCornerTodoSnapshotC
    var item5: JunimoCoreCornerTodoSnapshotC
    var item6: JunimoCoreCornerTodoSnapshotC
    var item7: JunimoCoreCornerTodoSnapshotC
    var item8: JunimoCoreCornerTodoSnapshotC
    var item9: JunimoCoreCornerTodoSnapshotC
    var item10: JunimoCoreCornerTodoSnapshotC
    var item11: JunimoCoreCornerTodoSnapshotC
    var item12: JunimoCoreCornerTodoSnapshotC
    var item13: JunimoCoreCornerTodoSnapshotC
    var item14: JunimoCoreCornerTodoSnapshotC
    var item15: JunimoCoreCornerTodoSnapshotC
}

@_silgen_name("junimo_core_engine_create")
private func junimoCoreEngineCreate() -> JunimoCoreEngineRef?

@_silgen_name("junimo_core_engine_destroy")
private func junimoCoreEngineDestroy(_ engine: JunimoCoreEngineRef?)

@_silgen_name("junimo_core_agents")
private func junimoCoreAgents(_ engine: JunimoCoreEngineRef?) -> JunimoCoreAgentListC

@_silgen_name("junimo_core_actions")
private func junimoCoreActions(_ engine: JunimoCoreEngineRef?) -> JunimoCoreActionListC

@_silgen_name("junimo_core_recent_activities")
private func junimoCoreRecentActivities(_ engine: JunimoCoreEngineRef?) -> JunimoCoreActivityListC

@_silgen_name("junimo_core_active_pomodoro")
private func junimoCoreActivePomodoro(_ engine: JunimoCoreEngineRef?) -> JunimoCorePomodoroSnapshotC

@_silgen_name("junimo_core_has_active_pomodoro")
private func junimoCoreHasActivePomodoro(_ engine: JunimoCoreEngineRef?) -> Int32

@_silgen_name("junimo_core_active_pomodoro_title")
private func junimoCoreActivePomodoroTitle(_ engine: JunimoCoreEngineRef?) -> UnsafePointer<CChar>?

@_silgen_name("junimo_core_active_pomodoro_started_at")
private func junimoCoreActivePomodoroStartedAt(_ engine: JunimoCoreEngineRef?) -> Int64

@_silgen_name("junimo_core_active_pomodoro_duration")
private func junimoCoreActivePomodoroDuration(_ engine: JunimoCoreEngineRef?) -> Int64

@_silgen_name("junimo_core_run_action")
private func junimoCoreRunAction(
    _ engine: JunimoCoreEngineRef?,
    _ actionID: UnsafePointer<CChar>?,
    _ unixSeconds: Int64
) -> JunimoCoreActionResultC

@_silgen_name("junimo_core_record_activity")
private func junimoCoreRecordActivity(
    _ engine: JunimoCoreEngineRef?,
    _ title: UnsafePointer<CChar>?,
    _ detail: UnsafePointer<CChar>?,
    _ unixSeconds: Int64
)

@_silgen_name("junimo_core_start_pomodoro")
private func junimoCoreStartPomodoro(
    _ engine: JunimoCoreEngineRef?,
    _ durationSeconds: Int64,
    _ unixSeconds: Int64
)

@_silgen_name("junimo_core_cancel_pomodoro")
private func junimoCoreCancelPomodoro(
    _ engine: JunimoCoreEngineRef?,
    _ unixSeconds: Int64
) -> JunimoCorePomodoroResultC

@_silgen_name("junimo_core_advance_time")
private func junimoCoreAdvanceTime(
    _ engine: JunimoCoreEngineRef?,
    _ unixSeconds: Int64
) -> JunimoCorePomodoroResultC

@_silgen_name("junimo_core_search_commands")
private func junimoCoreSearchCommands(
    _ engine: JunimoCoreEngineRef?,
    _ query: UnsafePointer<CChar>?
) -> JunimoCoreCommandListC

@_silgen_name("junimo_core_project_profile")
private func junimoCoreProjectProfile(
    _ engine: JunimoCoreEngineRef?
) -> JunimoCoreProjectProfileSnapshotC

@_silgen_name("junimo_core_recent_sessions")
private func junimoCoreRecentSessions(
    _ engine: JunimoCoreEngineRef?
) -> JunimoCoreSessionListC

@_silgen_name("junimo_core_ui_preferences")
private func junimoCoreUiPreferences(
    _ engine: JunimoCoreEngineRef?
) -> JunimoCoreUiPreferencesSnapshotC

@_silgen_name("junimo_core_set_accent")
private func junimoCoreSetAccent(
    _ engine: JunimoCoreEngineRef?,
    _ accent: UnsafePointer<CChar>?
) -> JunimoCoreUiPreferencesSnapshotC

@_silgen_name("junimo_core_set_density")
private func junimoCoreSetDensity(
    _ engine: JunimoCoreEngineRef?,
    _ density: UnsafePointer<CChar>?
) -> JunimoCoreUiPreferencesSnapshotC

@_silgen_name("junimo_core_ui_accent")
private func junimoCoreUiAccent(_ engine: JunimoCoreEngineRef?) -> UnsafePointer<CChar>?

@_silgen_name("junimo_core_ui_density")
private func junimoCoreUiDensity(_ engine: JunimoCoreEngineRef?) -> UnsafePointer<CChar>?

@_silgen_name("junimo_core_ui_expanded_width")
private func junimoCoreUiExpandedWidth(_ engine: JunimoCoreEngineRef?) -> Int32

@_silgen_name("junimo_core_ui_expanded_height")
private func junimoCoreUiExpandedHeight(_ engine: JunimoCoreEngineRef?) -> Int32

@_silgen_name("junimo_core_ui_top_offset")
private func junimoCoreUiTopOffset(_ engine: JunimoCoreEngineRef?) -> Int32

@_silgen_name("junimo_core_update_accent")
private func junimoCoreUpdateAccent(
    _ engine: JunimoCoreEngineRef?,
    _ accent: UnsafePointer<CChar>?
)

@_silgen_name("junimo_core_update_density")
private func junimoCoreUpdateDensity(
    _ engine: JunimoCoreEngineRef?,
    _ density: UnsafePointer<CChar>?
)

@_silgen_name("junimo_core_corner_note")
private func junimoCoreCornerNote(_ engine: JunimoCoreEngineRef?) -> JunimoCoreCornerNoteSnapshotC

@_silgen_name("junimo_core_update_corner_note_text")
private func junimoCoreUpdateCornerNoteText(
    _ engine: JunimoCoreEngineRef?,
    _ text: UnsafePointer<CChar>?
) -> JunimoCoreCornerNoteSnapshotC

@_silgen_name("junimo_core_add_corner_todo")
private func junimoCoreAddCornerTodo(
    _ engine: JunimoCoreEngineRef?,
    _ title: UnsafePointer<CChar>?
) -> JunimoCoreCornerNoteSnapshotC

@_silgen_name("junimo_core_update_corner_todo_title")
private func junimoCoreUpdateCornerTodoTitle(
    _ engine: JunimoCoreEngineRef?,
    _ id: UnsafePointer<CChar>?,
    _ title: UnsafePointer<CChar>?
) -> JunimoCoreCornerNoteSnapshotC

@_silgen_name("junimo_core_toggle_corner_todo")
private func junimoCoreToggleCornerTodo(
    _ engine: JunimoCoreEngineRef?,
    _ id: UnsafePointer<CChar>?
) -> JunimoCoreCornerNoteSnapshotC

@_silgen_name("junimo_core_remove_corner_todo")
private func junimoCoreRemoveCornerTodo(
    _ engine: JunimoCoreEngineRef?,
    _ id: UnsafePointer<CChar>?
) -> JunimoCoreCornerNoteSnapshotC

public struct CppActionResult: Equatable {
    public var handled: Bool
    public var activityTitle: String
    public var activityDetail: String
    public var agentID: String?
    public var agentStatus: AgentStatus?
}

public struct CppPomodoroResult: Equatable {
    public var changed: Bool
    public var completed: Bool
    public var activityTitle: String
    public var activityDetail: String
    public var notificationTitle: String
    public var notificationBody: String
}

public final class CppCoreEngine {
    private let handle: JunimoCoreEngineRef?

    public init?() {
        guard let handle = junimoCoreEngineCreate() else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        junimoCoreEngineDestroy(handle)
    }

    public func agents() -> [AgentSummary] {
        junimoCoreAgents(handle).agents
    }

    public func actions() -> [ConsoleAction] {
        junimoCoreActions(handle).actions
    }

    public func recentActivities() -> [ActivityEntry] {
        junimoCoreRecentActivities(handle).activities
    }

    public func activePomodoro() -> PomodoroSession? {
        guard junimoCoreHasActivePomodoro(handle) != 0 else {
            return nil
        }
        return PomodoroSession(
            title: string(from: junimoCoreActivePomodoroTitle(handle)),
            startedAt: Date(timeIntervalSince1970: TimeInterval(junimoCoreActivePomodoroStartedAt(handle))),
            duration: TimeInterval(junimoCoreActivePomodoroDuration(handle))
        )
    }

    public func runAction(id: String, at date: Date) -> CppActionResult {
        let result = id.withCString { pointer in
            junimoCoreRunAction(handle, pointer, unixSeconds(for: date))
        }

        return CppActionResult(
            handled: result.handled != 0,
            activityTitle: string(from: result.activityTitle),
            activityDetail: string(from: result.activityDetail),
            agentID: optionalString(from: result.agentID),
            agentStatus: AgentStatus(cppRawValue: result.agentStatus)
        )
    }

    public func recordActivity(title: String, detail: String, at date: Date) {
        title.withCString { titlePointer in
            detail.withCString { detailPointer in
                junimoCoreRecordActivity(handle, titlePointer, detailPointer, unixSeconds(for: date))
            }
        }
    }

    public func startPomodoro(duration: TimeInterval, at date: Date) {
        junimoCoreStartPomodoro(handle, Int64(duration), unixSeconds(for: date))
    }

    public func cancelPomodoro(at date: Date) -> CppPomodoroResult {
        CppPomodoroResult(junimoCoreCancelPomodoro(handle, unixSeconds(for: date)))
    }

    public func advanceTime(to date: Date) -> CppPomodoroResult {
        CppPomodoroResult(junimoCoreAdvanceTime(handle, unixSeconds(for: date)))
    }

    public func searchCommands(query: String) -> [CommandPaletteEntry] {
        let result = query.withCString { pointer in
            junimoCoreSearchCommands(handle, pointer)
        }
        return result.entries
    }

    public func projectProfile() -> ProjectProfileSummary {
        let snapshot = junimoCoreProjectProfile(handle)
        let shortcuts = [
            string(from: snapshot.shortcut1),
            string(from: snapshot.shortcut2),
            string(from: snapshot.shortcut3)
        ].filter { !$0.isEmpty }

        return ProjectProfileSummary(
            name: string(from: snapshot.name),
            path: string(from: snapshot.path),
            stack: string(from: snapshot.stack),
            shortcuts: shortcuts
        )
    }

    public func recentSessions() -> [ExecutionSessionSummary] {
        junimoCoreRecentSessions(handle).sessions
    }

    public func uiPreferences() -> ConsolePreferences {
        currentPreferences()
    }

    public func setAccent(_ accent: ConsoleAccent) -> ConsolePreferences {
        accent.rawValue.withCString { pointer in
            junimoCoreUpdateAccent(handle, pointer)
        }
        return currentPreferences()
    }

    public func setDensity(_ density: ConsoleDensity) -> ConsolePreferences {
        density.rawValue.withCString { pointer in
            junimoCoreUpdateDensity(handle, pointer)
        }
        return currentPreferences()
    }

    public func cornerNote() -> CornerNoteSnapshot {
        CornerNoteSnapshot(junimoCoreCornerNote(handle))
    }

    public func updateCornerNoteText(_ text: String) -> CornerNoteSnapshot {
        let snapshot = text.withCString { pointer in
            junimoCoreUpdateCornerNoteText(handle, pointer)
        }
        return CornerNoteSnapshot(snapshot)
    }

    public func addCornerTodo(title: String) -> CornerNoteSnapshot {
        let snapshot = title.withCString { pointer in
            junimoCoreAddCornerTodo(handle, pointer)
        }
        return CornerNoteSnapshot(snapshot)
    }

    public func updateCornerTodo(id: UUID, title: String) -> CornerNoteSnapshot {
        let idValue = id.uuidString
        let snapshot = idValue.withCString { idPointer in
            title.withCString { titlePointer in
                junimoCoreUpdateCornerTodoTitle(handle, idPointer, titlePointer)
            }
        }
        return CornerNoteSnapshot(snapshot)
    }

    public func toggleCornerTodo(id: UUID) -> CornerNoteSnapshot {
        let idValue = id.uuidString
        let snapshot = idValue.withCString { pointer in
            junimoCoreToggleCornerTodo(handle, pointer)
        }
        return CornerNoteSnapshot(snapshot)
    }

    public func removeCornerTodo(id: UUID) -> CornerNoteSnapshot {
        let idValue = id.uuidString
        let snapshot = idValue.withCString { pointer in
            junimoCoreRemoveCornerTodo(handle, pointer)
        }
        return CornerNoteSnapshot(snapshot)
    }

    private func unixSeconds(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970)
    }

    private func currentPreferences() -> ConsolePreferences {
        ConsolePreferences(
            accent: ConsoleAccent(rawValue: string(from: junimoCoreUiAccent(handle))) ?? .mint,
            density: ConsoleDensity(rawValue: string(from: junimoCoreUiDensity(handle))) ?? .comfortable,
            expandedWidth: Int(junimoCoreUiExpandedWidth(handle)),
            expandedHeight: Int(junimoCoreUiExpandedHeight(handle)),
            topOffset: Int(junimoCoreUiTopOffset(handle))
        )
    }
}

private extension ConsolePreferences {
    init(_ snapshot: JunimoCoreUiPreferencesSnapshotC) {
        self.init(
            accent: ConsoleAccent(rawValue: string(from: snapshot.accent)) ?? .mint,
            density: ConsoleDensity(rawValue: string(from: snapshot.density)) ?? .comfortable,
            expandedWidth: Int(snapshot.expandedWidth),
            expandedHeight: Int(snapshot.expandedHeight),
            topOffset: Int(snapshot.topOffset)
        )
    }
}

private extension JunimoCoreAgentListC {
    var agents: [AgentSummary] {
        let snapshots = [item0, item1, item2, item3, item4, item5, item6, item7]
        let boundedCount = max(0, min(Int(count), snapshots.count))
        return snapshots.prefix(boundedCount).map { snapshot in
            AgentSummary(
                id: string(from: snapshot.id),
                name: string(from: snapshot.name),
                status: AgentStatus(cppRawValue: snapshot.status) ?? .idle,
                detail: string(from: snapshot.detail)
            )
        }
    }
}

private extension JunimoCoreActionListC {
    var actions: [ConsoleAction] {
        let snapshots = [item0, item1, item2, item3, item4, item5, item6, item7]
        let boundedCount = max(0, min(Int(count), snapshots.count))
        return snapshots.prefix(boundedCount).map { snapshot in
            ConsoleAction(
                id: string(from: snapshot.id),
                title: string(from: snapshot.title),
                subtitle: string(from: snapshot.subtitle),
                kind: ConsoleActionKind(cppRawValue: snapshot.kind) ?? .tool,
                agentID: optionalString(from: snapshot.agentID)
            )
        }
    }
}

private extension JunimoCoreActivityListC {
    var activities: [ActivityEntry] {
        let snapshots = [item0, item1, item2, item3, item4, item5, item6, item7]
        let boundedCount = max(0, min(Int(count), snapshots.count))
        return snapshots.prefix(boundedCount).map { snapshot in
            ActivityEntry(
                title: string(from: snapshot.title),
                detail: string(from: snapshot.detail),
                date: Date(timeIntervalSince1970: TimeInterval(snapshot.createdAtUnixSeconds))
            )
        }
    }
}

private extension PomodoroSession {
    init?(_ snapshot: JunimoCorePomodoroSnapshotC) {
        guard snapshot.hasActive != 0 else {
            return nil
        }
        self.init(
            title: string(from: snapshot.title),
            startedAt: Date(timeIntervalSince1970: TimeInterval(snapshot.startedAtUnixSeconds)),
            duration: TimeInterval(snapshot.durationSeconds)
        )
    }
}

private extension JunimoCoreSessionListC {
    var sessions: [ExecutionSessionSummary] {
        let snapshots = [item0, item1, item2, item3, item4, item5]
        let boundedCount = max(0, min(Int(count), snapshots.count))
        return snapshots.prefix(boundedCount).map { snapshot in
            ExecutionSessionSummary(
                id: string(from: snapshot.id),
                title: string(from: snapshot.title),
                detail: string(from: snapshot.detail),
                status: ExecutionSessionStatus(rawValue: snapshot.status) ?? .queued,
                statusLabel: string(from: snapshot.statusLabel),
                startedAt: Date(timeIntervalSince1970: TimeInterval(snapshot.startedAtUnixSeconds))
            )
        }
    }
}

private extension JunimoCoreCommandListC {
    var entries: [CommandPaletteEntry] {
        let snapshots = [item0, item1, item2, item3, item4, item5, item6, item7]
        let boundedCount = max(0, min(Int(count), snapshots.count))
        return snapshots.prefix(boundedCount).map { snapshot in
            CommandPaletteEntry(
                id: string(from: snapshot.id),
                title: string(from: snapshot.title),
                subtitle: string(from: snapshot.subtitle),
                category: string(from: snapshot.category)
            )
        }
    }
}

private extension CornerNoteSnapshot {
    init(_ snapshot: JunimoCoreCornerNoteSnapshotC) {
        let snapshots = [
            snapshot.item0,
            snapshot.item1,
            snapshot.item2,
            snapshot.item3,
            snapshot.item4,
            snapshot.item5,
            snapshot.item6,
            snapshot.item7,
            snapshot.item8,
            snapshot.item9,
            snapshot.item10,
            snapshot.item11,
            snapshot.item12,
            snapshot.item13,
            snapshot.item14,
            snapshot.item15
        ]
        let boundedCount = max(0, min(Int(snapshot.todoCount), snapshots.count))
        self.init(
            text: string(from: snapshot.text),
            todos: snapshots.prefix(boundedCount).compactMap { todo in
                guard let id = UUID(uuidString: string(from: todo.id)) else {
                    return nil
                }
                return CornerTodoItem(
                    id: id,
                    title: string(from: todo.title),
                    isDone: todo.isDone != 0
                )
            }
        )
    }
}

private extension CppPomodoroResult {
    init(_ result: JunimoCorePomodoroResultC) {
        self.init(
            changed: result.changed != 0,
            completed: result.completed != 0,
            activityTitle: string(from: result.activityTitle),
            activityDetail: string(from: result.activityDetail),
            notificationTitle: string(from: result.notificationTitle),
            notificationBody: string(from: result.notificationBody)
        )
    }
}

private extension AgentStatus {
    init?(cppRawValue: Int32) {
        switch cppRawValue {
        case 0:
            self = .idle
        case 1:
            self = .running
        case 2:
            self = .succeeded
        case 3:
            self = .failed
        default:
            return nil
        }
    }
}

private extension ConsoleActionKind {
    init?(cppRawValue: Int32) {
        switch cppRawValue {
        case 0:
            self = .agent
        case 1:
            self = .tool
        case 2:
            self = .project
        default:
            return nil
        }
    }
}

private func string(from pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else {
        return ""
    }
    return String(cString: pointer)
}

private func optionalString(from pointer: UnsafePointer<CChar>?) -> String? {
    let value = string(from: pointer)
    return value.isEmpty ? nil : value
}
