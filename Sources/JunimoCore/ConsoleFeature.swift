import Foundation

public struct ConsoleAgentStartEffect: Equatable {
    public var agentID: String
    public var detail: String
    public var date: Date

    /// 业务语义：agent start effect 只描述 action 已启动 agent，不直接绑定任何具体 adapter。
    public init(agentID: String, detail: String, date: Date) {
        self.agentID = agentID
        self.detail = detail
        self.date = date
    }
}

public struct ConsoleFeatureEffects: Equatable {
    public var agentStarts: [ConsoleAgentStartEffect]

    /// 业务语义：console effects 默认为空，避免 unknown action 伪造外部启动。
    public init(agentStarts: [ConsoleAgentStartEffect] = []) {
        self.agentStarts = agentStarts
    }

    public var isEmpty: Bool {
        agentStarts.isEmpty
    }
}

public struct ConsoleFeature {
    public private(set) var agents: [AgentSummary]
    public private(set) var actions: [ConsoleAction]
    public private(set) var recentActivities: [ActivityEntry]
    public private(set) var commandQuery: String
    public private(set) var commandResults: [CommandPaletteEntry]
    public private(set) var projectProfile: ProjectProfileSummary
    public private(set) var sessions: [ExecutionSessionSummary]

    private let core: ActionCore & CommandCatalogCore & SessionTimelineCore & ConsoleStateCore

    /// 业务语义：ConsoleFeature 以 core snapshots 初始化 console shell 投影，coordinator 只做兼容暴露。
    public init(core: ActionCore & CommandCatalogCore & SessionTimelineCore & ConsoleStateCore) {
        self.core = core
        self.agents = core.agents()
        self.actions = core.actions()
        self.recentActivities = core.recentActivities()
        self.commandQuery = ""
        self.commandResults = core.searchCommands(query: "")
        self.projectProfile = core.projectProfile()
        self.sessions = core.recentSessions()
    }

    /// 业务语义：命令查询只更新 command projection，避免搜索状态散落在 coordinator 和 view 中。
    public mutating func updateCommandQuery(_ query: String) {
        commandQuery = query
        commandResults = core.searchCommands(query: query)
    }

    /// 业务语义：action 执行通过 core 完成，running agent 以 effect 暴露给上层 bridge。
    public mutating func performAction(id: String, now: Date) -> ConsoleFeatureEffects {
        guard let action = actions.first(where: { $0.id == id }) else {
            return ConsoleFeatureEffects()
        }

        let result = core.run(action: action, at: now)
        refreshState()
        guard let agentID = result.agentID, result.agentStatus == .running else {
            return ConsoleFeatureEffects()
        }

        return ConsoleFeatureEffects(
            agentStarts: [
                ConsoleAgentStartEffect(agentID: agentID, detail: result.detail, date: now)
            ]
        )
    }

    /// 业务语义：外部 feature 产生 activity effect 时，ConsoleFeature 负责同步 activity/session 投影。
    public mutating func recordActivity(title: String, detail: String, date: Date) {
        core.recordActivity(title: title, detail: detail, at: date)
        refreshActivityProjection()
    }

    /// 业务语义：Codex 等 feature 可以更新 agent UI 投影，但不接管 console action catalog。
    public mutating func updateAgentProjection(id: String, status: AgentStatus, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else {
            return
        }
        agents[index].status = status
        agents[index].detail = detail
    }

    /// 业务语义：core 状态变化后统一刷新 console shell 投影，调用方不直接访问多个 core 协议。
    public mutating func refreshState() {
        agents = core.agents()
        actions = core.actions()
        recentActivities = core.recentActivities()
        sessions = core.recentSessions()
    }

    /// 业务语义：activity/session 是同一执行时间线的投影，记录 activity 后一起刷新。
    private mutating func refreshActivityProjection() {
        recentActivities = core.recentActivities()
        sessions = core.recentSessions()
    }
}
