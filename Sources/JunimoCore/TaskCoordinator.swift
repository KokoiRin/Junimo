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
    @Published public private(set) var codexReviewItems: [CodexReviewItem]
    @Published public private(set) var preferences: ConsolePreferences
    @Published public var theme: ConsoleTheme
    @Published public private(set) var activePomodoro: PomodoroSession?
    @Published public private(set) var pendingNotifications: [NotificationRequest]
    @Published public private(set) var selfUpdateSnapshot: SelfUpdateSnapshot
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
    private var pomodoroFeature: PomodoroFeature
    private var codexFeature: CodexFeature
    private var cornerNoteFeature: CornerNoteFeature
    private var preferencesFeature: PreferencesFeature
    private var notificationOutbox: NotificationOutbox
    private var selfUpdateFeature: SelfUpdateFeature
    private var nowProvider: () -> Date

    public init(
        core: (ActionCore & PomodoroCore & CommandCatalogCore & SessionTimelineCore & PreferencesCore & ConsoleStateCore & CornerNoteCore)? = CppBackedCore(),
        currentVersion: ReleaseVersion = ReleaseVersion("0.1.11")!,
        now: Date = Date(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedCore = core ?? SwiftFallbackCore()
        self.consoleFeature = ConsoleFeature(core: resolvedCore)
        self.pomodoroFeature = PomodoroFeature(core: resolvedCore)
        self.codexFeature = CodexFeature(now: now)
        self.cornerNoteFeature = CornerNoteFeature(core: resolvedCore)
        self.preferencesFeature = PreferencesFeature(core: resolvedCore)
        self.notificationOutbox = NotificationOutbox()
        self.selfUpdateFeature = SelfUpdateFeature(currentVersion: currentVersion)
        self.nowProvider = nowProvider
        self.agents = consoleFeature.agents
        self.actions = consoleFeature.actions
        self.recentActivities = consoleFeature.recentActivities
        self.commandQuery = consoleFeature.commandQuery
        self.commandResults = consoleFeature.commandResults
        self.projectProfile = consoleFeature.projectProfile
        self.sessions = consoleFeature.sessions
        self.codexMonitor = codexFeature.monitor
        self.codexReviewItems = codexFeature.reviewItems
        self.preferences = preferencesFeature.preferences
        self.theme = preferencesFeature.theme
        self.activePomodoro = pomodoroFeature.activePomodoro
        self.pendingNotifications = notificationOutbox.pending
        self.selfUpdateSnapshot = selfUpdateFeature.snapshot
        self.cornerNoteText = cornerNoteFeature.snapshot.text
        self.cornerTodos = cornerNoteFeature.snapshot.todos
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

    /// 业务语义：coordinator 只转发 action intent，console feature 返回的 effects 再接入兼容桥。
    public func performAction(id: String, now: Date? = nil) {
        let date = now ?? nowProvider()
        let effects = consoleFeature.performAction(id: id, now: date)
        syncConsoleFeatureProjection()
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
        layoutPreferencesDidChange?(updated)
    }

    /// 业务语义：coordinator 只转发 density intent，并保留既有 layout callback 兼容路径。
    public func setDensity(_ density: ConsoleDensity) {
        let updated = preferencesFeature.setDensity(density)
        syncPreferencesFeatureProjection()
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
    }

    /// 业务语义：coordinator 只转发取消 Pomodoro 意图，取消规则和活动记录仍由 core 处理。
    public func cancelPomodoro(now: Date? = nil) {
        let date = now ?? nowProvider()
        if pomodoroFeature.cancel(now: date) {
            syncPomodoroFeatureProjection()
            refreshConsoleState()
        }
    }

    public func markNotificationDelivered(id: UUID) {
        objectWillChange.send()
        notificationOutbox.markDelivered(id: id)
        syncNotificationOutboxProjection()
    }

    /// 业务语义：coordinator 只转发更新检查 intent，版本状态由 SelfUpdateFeature 维护。
    public func startSelfUpdateCheck(now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startSelfUpdateCheck(now: now)
            }
            return
        }
        objectWillChange.send()
        selfUpdateFeature.startChecking(now: now ?? nowProvider())
        syncSelfUpdateFeatureProjection()
    }

    /// 业务语义：release 检查结果通过 SelfUpdateFeature 转成公开投影，coordinator 不做网络解释。
    public func applySelfUpdateCheck(_ result: SelfUpdateCheckResult, now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applySelfUpdateCheck(result, now: now)
            }
            return
        }
        objectWillChange.send()
        selfUpdateFeature.applyReleaseCheck(result, now: now ?? nowProvider())
        syncSelfUpdateFeatureProjection()
    }

    /// 业务语义：安装 intent 必须先经过 SelfUpdateFeature 的可安装状态门禁。
    public func startSelfUpdateInstall(now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startSelfUpdateInstall(now: now)
            }
            return
        }
        objectWillChange.send()
        selfUpdateFeature.startInstalling(now: now ?? nowProvider())
        syncSelfUpdateFeatureProjection()
    }

    /// 业务语义：外部 updater 启动失败要回写可见状态，方便用户重试。
    public func failSelfUpdateInstall(message: String, now: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.failSelfUpdateInstall(message: message, now: now)
            }
            return
        }
        objectWillChange.send()
        selfUpdateFeature.applyInstallFailure(message: message, now: now ?? nowProvider())
        syncSelfUpdateFeatureProjection()
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
    }

    /// 业务语义：collapsed 快捷确认由 Codex feature 决定最新 review 是哪一个。
    public func acknowledgeLatestCodexReview() {
        objectWillChange.send()
        codexFeature.acknowledgeLatestReview()
        syncCodexFeatureProjection()
    }

    public func setCornerNoteExpanded(_ isExpanded: Bool) {
        cornerNoteFeature.setExpanded(isExpanded)
        syncCornerNoteFeatureProjection()
    }

    public func updateCornerNoteText(_ text: String) {
        cornerNoteFeature.updateText(text)
        syncCornerNoteFeatureProjection()
    }

    public func addCornerTodo(title: String = "") {
        cornerNoteFeature.addTodo(title: title)
        syncCornerNoteFeatureProjection()
    }

    public func updateCornerTodo(id: UUID, title: String) {
        cornerNoteFeature.updateTodo(id: id, title: title)
        syncCornerNoteFeatureProjection()
    }

    public func toggleCornerTodo(id: UUID) {
        cornerNoteFeature.toggleTodo(id: id)
        syncCornerNoteFeatureProjection()
    }

    public func removeCornerTodo(id: UUID) {
        cornerNoteFeature.removeTodo(id: id)
        syncCornerNoteFeatureProjection()
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

    /// 业务语义：coordinator 只同步 SelfUpdateFeature 快照，避免成为第二个更新状态 owner。
    private func syncSelfUpdateFeatureProjection() {
        selfUpdateSnapshot = selfUpdateFeature.snapshot
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
