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

@_silgen_name("junimo_core_engine_create")
private func junimoCoreEngineCreate() -> JunimoCoreEngineRef?

@_silgen_name("junimo_core_engine_destroy")
private func junimoCoreEngineDestroy(_ engine: JunimoCoreEngineRef?)

@_silgen_name("junimo_core_run_action")
private func junimoCoreRunAction(
    _ engine: JunimoCoreEngineRef?,
    _ actionID: UnsafePointer<CChar>?,
    _ unixSeconds: Int64
) -> JunimoCoreActionResultC

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
