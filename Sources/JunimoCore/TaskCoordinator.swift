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
    @Published public private(set) var diagnosticLogs: [DiagnosticLogEntry]
    @Published public private(set) var activityCaptureStats: ActivityCaptureDailyStats
    @Published public private(set) var codexMonitor: CodexMonitorSnapshot
    @Published public private(set) var codexReviewItems: [CodexReviewItem]
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

    private var consoleFeature: ConsoleFeature
    private var diagnosticLogFeature: DiagnosticLogFeature
    private var activityCaptureStatsFeature: ActivityCaptureStatsFeature
    private var pomodoroFeature: PomodoroFeature
    private var codexFeature: CodexFeature
    private var cornerNoteFeature: CornerNoteFeature
    private var preferencesFeature: PreferencesFeature
    private var notificationOutbox: NotificationOutbox
    private var nowProvider: () -> Date
    private var nextActivityCaptureStatsRefresh: Date

    public init(
        core: (ActionCore & PomodoroCore & CommandCatalogCore & SessionTimelineCore & PreferencesCore & ConsoleStateCore & CornerNoteCore)? = CppBackedCore(),
        captureDirectory: URL? = nil,
        now: Date = Date(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedCore = core ?? SwiftFallbackCore()
        self.consoleFeature = ConsoleFeature(core: resolvedCore)
        self.diagnosticLogFeature = DiagnosticLogFeature(now: now)
        self.activityCaptureStatsFeature = ActivityCaptureStatsFeature(rootDirectory: captureDirectory, now: now)
        self.pomodoroFeature = PomodoroFeature(core: resolvedCore)
        self.codexFeature = CodexFeature(now: now)
        self.cornerNoteFeature = CornerNoteFeature(core: resolvedCore)
        self.preferencesFeature = PreferencesFeature(core: resolvedCore)
        self.notificationOutbox = NotificationOutbox()
        self.nowProvider = nowProvider
        self.nextActivityCaptureStatsRefresh = now.addingTimeInterval(60)
        self.agents = consoleFeature.agents
        self.actions = consoleFeature.actions
        self.recentActivities = consoleFeature.recentActivities
        self.commandQuery = consoleFeature.commandQuery
        self.commandResults = consoleFeature.commandResults
        self.projectProfile = consoleFeature.projectProfile
        self.sessions = consoleFeature.sessions
        self.diagnosticLogs = diagnosticLogFeature.entries
        self.activityCaptureStats = activityCaptureStatsFeature.todayStats
        self.codexMonitor = codexFeature.monitor
        self.codexReviewItems = codexFeature.reviewItems
        self.preferences = preferencesFeature.preferences
        self.theme = preferencesFeature.theme
        self.activePomodoro = pomodoroFeature.activePomodoro
        self.pendingNotifications = notificationOutbox.pending
        self.cornerNoteText = cornerNoteFeature.snapshot.text
        self.cornerTodos = cornerNoteFeature.snapshot.todos
    }

    public func pointerEntered(at date: Date? = nil) {
        guard !isExpanded else {
            return
        }
        isExpanded = true
        recordDiagnosticLog(
            level: .info,
            source: .app,
            title: "主面板展开",
            detail: "用户进入顶部控制台热区",
            date: date ?? nowProvider()
        )
    }

    public func pointerExited(at date: Date? = nil) {
        guard isExpanded else {
            return
        }
        isExpanded = false
        recordDiagnosticLog(
            level: .debug,
            source: .app,
            title: "主面板收起",
            detail: "用户离开顶部控制台热区",
            date: date ?? nowProvider()
        )
    }

    public func advanceTime(to date: Date) {
        completePomodoroIfNeeded(now: date)
        refreshActivityCaptureStatsIfNeeded(now: date)
    }

    /// 业务语义：coordinator 只转发 action intent，console feature 返回的 effects 再接入兼容桥。
    public func performAction(id: String, now: Date? = nil) {
        let date = now ?? nowProvider()
        let effects = consoleFeature.performAction(id: id, now: date)
        syncConsoleFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: logSource(forActionID: id),
            title: "执行动作",
            detail: id,
            date: date
        )
        consumeConsoleFeatureEffects(effects)
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

    /// 业务语义：coordinator 只转发 accent intent，preferences/theme 投影由 PreferencesFeature 维护。
    public func setAccent(_ accent: ConsoleAccent) {
        let updated = preferencesFeature.setAccent(accent)
        syncPreferencesFeatureProjection()
        recordDiagnosticLog(
            level: .debug,
            source: .app,
            title: "主题更新",
            detail: accent.rawValue,
            date: nowProvider()
        )
        layoutPreferencesDidChange?(updated)
    }

    /// 业务语义：coordinator 只转发 density intent，并保留既有 layout callback 兼容路径。
    public func setDensity(_ density: ConsoleDensity) {
        let updated = preferencesFeature.setDensity(density)
        syncPreferencesFeatureProjection()
        recordDiagnosticLog(
            level: .debug,
            source: .app,
            title: "布局密度更新",
            detail: density.rawValue,
            date: nowProvider()
        )
        layoutPreferencesDidChange?(updated)
    }

    /// 业务语义：coordinator 只转发 command query，搜索状态由 ConsoleFeature 拥有。
    public func updateCommandQuery(_ query: String) {
        consoleFeature.updateCommandQuery(query)
        syncConsoleFeatureProjection()
    }

    /// 业务语义：coordinator 只转发启动 Pomodoro 意图，并同步 feature/core 的公开投影。
    public func startPomodoro(duration: TimeInterval = 25 * 60, now: Date? = nil) {
        let date = now ?? nowProvider()
        pomodoroFeature.start(duration: duration, now: date)
        syncPomodoroFeatureProjection()
        refreshConsoleState()
        recordDiagnosticLog(
            level: .info,
            source: .focus,
            title: "专注开始",
            detail: "\(Int(duration)) 秒",
            date: date
        )
    }

    /// 业务语义：coordinator 只转发取消 Pomodoro 意图，取消规则和活动记录仍由 core 处理。
    public func cancelPomodoro(now: Date? = nil) {
        let date = now ?? nowProvider()
        if pomodoroFeature.cancel(now: date) {
            syncPomodoroFeatureProjection()
            refreshConsoleState()
            recordDiagnosticLog(
                level: .info,
                source: .focus,
                title: "专注停止",
                detail: "用户取消当前专注",
                date: date
            )
        }
    }

    public func markNotificationDelivered(id: UUID) {
        objectWillChange.send()
        notificationOutbox.markDelivered(id: id)
        syncNotificationOutboxProjection()
        recordDiagnosticLog(
            level: .debug,
            source: .app,
            title: "通知已投递",
            detail: id.uuidString,
            date: nowProvider()
        )
    }

    /// 业务语义：collapsed 刘海右侧优先显示待处理结果，其次显示活跃 Codex 状态，最后显示配额。
    public var codexCollapsedStatusText: String {
        codexFeature.collapsedStatusText
    }

    /// 业务语义：诊断和兼容层通过 Codex feature 快照读取状态，不能重新拥有 Codex 规则。
    public var codexFeatureSnapshot: CodexFeatureSnapshot {
        codexFeature.snapshot
    }

    /// 业务语义：coordinator 只把确认意图转发给 Codex feature，不直接拥有 review 状态。
    public func acknowledgeCodexReview(id: String) {
        objectWillChange.send()
        codexFeature.acknowledgeReview(id: id)
        syncCodexFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: .codex,
            title: "Codex 结果已确认",
            detail: id,
            date: nowProvider()
        )
    }

    /// 业务语义：collapsed 快捷确认由 Codex feature 决定最新 review 是哪一个。
    public func acknowledgeLatestCodexReview() {
        objectWillChange.send()
        codexFeature.acknowledgeLatestReview()
        syncCodexFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: .codex,
            title: "最新 Codex 结果已确认",
            detail: "用户清除了最近一条待确认结果",
            date: nowProvider()
        )
    }

    public func setCornerNoteExpanded(_ isExpanded: Bool) {
        cornerNoteFeature.setExpanded(isExpanded)
        syncCornerNoteFeatureProjection()
        recordDiagnosticLog(
            level: .debug,
            source: .note,
            title: isExpanded ? "便签打开" : "便签关闭",
            detail: "右下角便签面板状态变化",
            date: nowProvider()
        )
    }

    public func updateCornerNoteText(_ text: String) {
        cornerNoteFeature.updateText(text)
        syncCornerNoteFeatureProjection()
    }

    public func addCornerTodo(title: String = "") {
        cornerNoteFeature.addTodo(title: title)
        syncCornerNoteFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: .note,
            title: "新增待办",
            detail: title.isEmpty ? "空白待办" : title,
            date: nowProvider()
        )
    }

    public func updateCornerTodo(id: UUID, title: String) {
        cornerNoteFeature.updateTodo(id: id, title: title)
        syncCornerNoteFeatureProjection()
    }

    public func toggleCornerTodo(id: UUID) {
        cornerNoteFeature.toggleTodo(id: id)
        syncCornerNoteFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: .note,
            title: "待办状态切换",
            detail: id.uuidString,
            date: nowProvider()
        )
    }

    public func removeCornerTodo(id: UUID) {
        cornerNoteFeature.removeTodo(id: id)
        syncCornerNoteFeatureProjection()
        recordDiagnosticLog(
            level: .info,
            source: .note,
            title: "删除待办",
            detail: id.uuidString,
            date: nowProvider()
        )
    }

    /// 业务语义：手动调试探针只写入诊断日志，用于确认日志链路可用。
    public func recordDebugProbe(now: Date? = nil) {
        diagnosticLogFeature.recordDebugProbe(now: now ?? nowProvider())
        syncDiagnosticLogProjection()
    }

    /// 业务语义：截图统计只刷新本地落盘数据，不启动截图进程。
    public func refreshActivityCaptureStats(now: Date? = nil) {
        activityCaptureStatsFeature.refresh(now: now ?? nowProvider())
        syncActivityCaptureStatsProjection()
    }

    /// 业务语义：snapshot 只更新观测到的状态，不能把缺失线程伪造成完成。
    public func refreshCodexMonitor(_ snapshot: CodexMonitorSnapshot, now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshCodexMonitor(snapshot, now: now)
            }
            return
        }
        objectWillChange.send()
        let date = now ?? nowProvider()
        let effects = codexFeature.refreshMonitor(snapshot, now: date)
        syncCodexFeatureProjection()
        recordDiagnosticLog(
            level: snapshot.usage.status == .available ? .info : .warning,
            source: .codex,
            title: "Codex 状态刷新",
            detail: snapshot.usage.summaryText,
            date: date
        )
        consumeCodexFeatureEffects(effects)
    }

    /// 业务语义：realtime 事件是明确生命周期迁移的入口，terminal review 只能从这里或等价显式状态进入。
    public func applyCodexRealtimeEvent(_ event: CodexRealtimeEvent, now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyCodexRealtimeEvent(event, now: now)
            }
            return
        }
        objectWillChange.send()
        let date = now ?? nowProvider()
        let effects = codexFeature.applyRealtimeEvent(event, now: date)
        syncCodexFeatureProjection()
        recordDiagnosticLog(
            level: .debug,
            source: .codex,
            title: "Codex 实时事件",
            detail: "\(event)",
            date: date
        )
        consumeCodexFeatureEffects(effects)
    }

    /// 业务语义：统一应用单个 Codex 线程生命周期，并只对明确 terminal 迁移产生 review。
    public func updateCodexThread(id: String, title: String, status: CodexThreadStatus, detail: String, now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateCodexThread(id: id, title: title, status: status, detail: detail, now: now)
            }
            return
        }
        objectWillChange.send()
        let date = now ?? nowProvider()
        let effects = codexFeature.updateThread(id: id, title: title, status: status, detail: detail, now: date)
        syncCodexFeatureProjection()
        recordDiagnosticLog(
            level: status == .failed ? .error : .info,
            source: .codex,
            title: "Codex 线程更新",
            detail: "\(title) · \(status.rawValue)",
            date: date
        )
        consumeCodexFeatureEffects(effects)
    }

    /// 业务语义：Pomodoro 完成 effect 只从 PomodoroFeature 进入通知 outbox。
    private func completePomodoroIfNeeded(now: Date) {
        let effects = pomodoroFeature.advanceTime(to: now)
        syncPomodoroFeatureProjection()
        guard !effects.isEmpty else {
            return
        }
        notificationOutbox.enqueue(contentsOf: effects.notifications)
        syncNotificationOutboxProjection()
        refreshConsoleState()
        recordDiagnosticLog(
            level: .info,
            source: .focus,
            title: "专注完成",
            detail: effects.notifications.first?.title ?? "提醒已创建",
            date: now
        )
    }

    /// 业务语义：截图统计是低频辅助信息，避免每次 UI timer tick 都扫描文件系统。
    private func refreshActivityCaptureStatsIfNeeded(now: Date) {
        guard now >= nextActivityCaptureStatsRefresh else {
            return
        }
        nextActivityCaptureStatsRefresh = now.addingTimeInterval(60)
        refreshActivityCaptureStats(now: now)
    }

    /// 业务语义：coordinator 暴露诊断日志投影，但不重新拥有日志裁剪规则。
    private func syncDiagnosticLogProjection() {
        diagnosticLogs = diagnosticLogFeature.entries
    }

    private func syncActivityCaptureStatsProjection() {
        activityCaptureStats = activityCaptureStatsFeature.todayStats
    }

    /// 业务语义：所有 coordinator 级日志写入统一经过 feature，保持日志顺序和上限一致。
    private func recordDiagnosticLog(
        level: DiagnosticLogLevel,
        source: DiagnosticLogSource,
        title: String,
        detail: String,
        date: Date
    ) {
        diagnosticLogFeature.record(level: level, source: source, title: title, detail: detail, date: date)
        syncDiagnosticLogProjection()
    }

    /// 业务语义：action id 到日志来源的映射只用于诊断归类，不改变 action 执行语义。
    private func logSource(forActionID id: String) -> DiagnosticLogSource {
        switch id {
        case "codex":
            return .codex
        case "pomodoro-25", "pomodoro-10s":
            return .focus
        default:
            return .app
        }
    }

    private func updateAgent(id: String, status: AgentStatus, detail: String) {
        consoleFeature.updateAgentProjection(id: id, status: status, detail: detail)
        syncConsoleFeatureProjection()
    }

    /// 业务语义：兼容 coordinator 只同步 Codex feature 的公开投影，避免成为第二个 Codex 状态 owner。
    private func syncCodexFeatureProjection() {
        codexMonitor = codexFeature.monitor
        codexReviewItems = codexFeature.reviewItems
        let projection = codexFeature.agentProjection
        updateAgent(id: "codex", status: projection.status, detail: projection.detail)
    }

    /// 业务语义：Codex feature 产生副作用请求，coordinator 负责落到现有通知队列和活动时间线。
    private func consumeCodexFeatureEffects(_ effects: CodexFeatureEffects) {
        notificationOutbox.enqueue(contentsOf: effects.notifications)
        syncNotificationOutboxProjection()
        for activity in effects.activities {
            recordActivity(title: activity.title, detail: activity.detail, date: activity.date)
        }
    }

    /// 业务语义：Codex 状态只来自 adapter 观测，console action 不能伪造 running thread。
    private func consumeConsoleFeatureEffects(_ effects: ConsoleFeatureEffects) {
        _ = effects
    }

    /// 业务语义：coordinator 暴露通知队列投影给 app shell，但不直接拥有 outbox 状态。
    private func syncNotificationOutboxProjection() {
        pendingNotifications = notificationOutbox.pending
    }

    /// 业务语义：coordinator 只同步 PomodoroFeature 投影，避免重新拥有 timer effect 规则。
    private func syncPomodoroFeatureProjection() {
        activePomodoro = pomodoroFeature.activePomodoro
    }

    /// 业务语义：外部 feature 记录 console activity 时仍通过 ConsoleFeature 同步 timeline 投影。
    private func recordActivity(title: String, detail: String, date: Date) {
        consoleFeature.recordActivity(title: title, detail: detail, date: date)
        syncConsoleFeatureProjection()
    }

    /// 业务语义：console state refresh 只刷新 action/catalog/activity/session 投影。
    private func refreshConsoleState() {
        consoleFeature.refreshState()
        syncConsoleFeatureProjection()
    }

    /// 业务语义：coordinator 只同步 ConsoleFeature 的公开投影，避免重新拥有 action/catalog/session 状态。
    private func syncConsoleFeatureProjection() {
        agents = consoleFeature.agents
        actions = consoleFeature.actions
        recentActivities = consoleFeature.recentActivities
        commandQuery = consoleFeature.commandQuery
        commandResults = consoleFeature.commandResults
        projectProfile = consoleFeature.projectProfile
        sessions = consoleFeature.sessions
    }

    /// 业务语义：coordinator 只同步 PreferencesFeature 投影，layout callback 留在兼容层。
    private func syncPreferencesFeatureProjection() {
        preferences = preferencesFeature.preferences
        theme = preferencesFeature.theme
    }

    /// 业务语义：coordinator 只同步 CornerNoteFeature 的公开投影，避免成为第二个便签状态 owner。
    private func syncCornerNoteFeatureProjection() {
        isCornerNoteExpanded = cornerNoteFeature.snapshot.isExpanded
        cornerNoteText = cornerNoteFeature.snapshot.text
        cornerTodos = cornerNoteFeature.snapshot.todos
    }
}
