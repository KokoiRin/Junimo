import Foundation

public struct CodexFeatureActivityEffect: Equatable {
    public var title: String
    public var detail: String
    public var date: Date

    /// 业务语义：Codex feature 只请求活动记录副作用，不直接写入全局时间线。
    public init(title: String, detail: String, date: Date) {
        self.title = title
        self.detail = detail
        self.date = date
    }
}

public struct CodexFeatureEffects: Equatable {
    public var notifications: [NotificationRequest]
    public var activities: [CodexFeatureActivityEffect]

    public static let none = CodexFeatureEffects()

    /// 业务语义：effects 是 feature 向 runtime 请求的副作用集合，空集合表示纯状态迁移。
    public init(notifications: [NotificationRequest] = [], activities: [CodexFeatureActivityEffect] = []) {
        self.notifications = notifications
        self.activities = activities
    }

    public var isEmpty: Bool {
        notifications.isEmpty && activities.isEmpty
    }

    /// 业务语义：批量事件需要保留每个状态迁移产生的副作用，交给 runtime 顺序执行。
    public mutating func append(_ other: CodexFeatureEffects) {
        notifications.append(contentsOf: other.notifications)
        activities.append(contentsOf: other.activities)
    }
}

public struct CodexFeatureAgentProjection: Equatable {
    public var status: AgentStatus
    public var detail: String

    /// 业务语义：Codex agent 概览是 feature 生命周期状态的只读投影。
    public init(status: AgentStatus, detail: String) {
        self.status = status
        self.detail = detail
    }
}

public struct CodexFeatureSnapshot: Equatable {
    public var monitor: CodexMonitorSnapshot
    public var reviewItems: [CodexReviewItem]
    public var collapsedStatusText: String
    public var agentProjection: CodexFeatureAgentProjection

    /// 业务语义：诊断和兼容层只能读取 Codex feature 的公开快照，不拥有内部状态。
    public init(
        monitor: CodexMonitorSnapshot,
        reviewItems: [CodexReviewItem],
        collapsedStatusText: String,
        agentProjection: CodexFeatureAgentProjection
    ) {
        self.monitor = monitor
        self.reviewItems = reviewItems
        self.collapsedStatusText = collapsedStatusText
        self.agentProjection = agentProjection
    }
}

public struct CodexFeature {
    public private(set) var monitor: CodexMonitorSnapshot
    public private(set) var reviewItems: [CodexReviewItem]

    /// 业务语义：Codex feature 初始化后即成为 quota、thread lifecycle 和 review attention 的唯一 owner。
    public init(now: Date, monitor: CodexMonitorSnapshot? = nil, reviewItems: [CodexReviewItem] = []) {
        self.monitor = monitor ?? CodexMonitorSnapshot.researchedDefault(now: now)
        self.reviewItems = reviewItems.sorted { $0.createdAt > $1.createdAt }
    }

    /// 业务语义：collapsed 刘海右侧优先显示待处理结果，其次显示活跃 Codex 状态，最后显示配额。
    public var collapsedStatusText: String {
        if let review = reviewItems.first {
            return review.cueText
        }
        if let activeThread = monitor.threads.first(where: { $0.status.isActive }) {
            return activeThread.status == .waiting ? "Codex waiting" : "Codex running"
        }
        if monitor.openThreadCount > 0 {
            return "Codex open \(monitor.openThreadCount)"
        }
        return monitor.usage.summaryText
    }

    public var snapshot: CodexFeatureSnapshot {
        CodexFeatureSnapshot(
            monitor: monitor,
            reviewItems: reviewItems,
            collapsedStatusText: collapsedStatusText,
            agentProjection: agentProjection
        )
    }

    /// 业务语义：Codex agent 概览从 normalized lifecycle 派生，不直接读取原始协议状态。
    public var agentProjection: CodexFeatureAgentProjection {
        let activeCount = monitor.activeThreadCount
        if activeCount > 0 {
            return CodexFeatureAgentProjection(
                status: .running,
                detail: "\(activeCount) Codex thread\(activeCount == 1 ? "" : "s") active"
            )
        }

        if monitor.openThreadCount > 0 {
            return CodexFeatureAgentProjection(
                status: .idle,
                detail: "\(monitor.openThreadCount) Codex thread\(monitor.openThreadCount == 1 ? "" : "s") open"
            )
        }

        if let latest = monitor.latestThread, latest.status.isTerminal {
            return CodexFeatureAgentProjection(
                status: latest.status == .failed ? .failed : .succeeded,
                detail: latest.detail
            )
        }

        return CodexFeatureAgentProjection(status: .idle, detail: monitor.usage.detail)
    }

    /// 业务语义：snapshot 只更新观测到的状态，不能把缺失线程伪造成完成。
    @discardableResult
    public mutating func refreshMonitor(_ snapshot: CodexMonitorSnapshot, now: Date) -> CodexFeatureEffects {
        let incomingThreadIDs = Set(snapshot.threads.map(\.id))
        let incomingFindingIDs = Set(snapshot.findings.map(\.id))
        let transientStreamFindings = monitor.findings.filter { finding in
            !incomingFindingIDs.contains(finding.id)
                && (finding.id.contains("realtime") || finding.id.contains("stream"))
        }
        let retainedNonIncomingWork = monitor.threads.filter { thread in
            thread.status.isNonTerminalWork && !incomingThreadIDs.contains(thread.id)
        }

        monitor.usage = snapshot.usage
        monitor.findings = snapshot.findings + transientStreamFindings
        monitor.refreshedAt = snapshot.refreshedAt
        monitor.threadCounts = snapshot.threadCounts
        monitor.threads.removeAll { thread in
            !thread.status.isNonTerminalWork && !incomingThreadIDs.contains(thread.id)
        }

        var effects = CodexFeatureEffects.none
        for thread in snapshot.threads {
            effects.append(
                updateThread(
                    id: thread.id,
                    title: thread.title,
                    status: thread.status,
                    detail: thread.detail,
                    now: thread.updatedAt
                )
            )
        }

        let reducedThreads = CodexThreadLifecycleReducer.reduce(threads: monitor.threads).visibleThreads
        let retainedCounts = CodexThreadCounts.from(retainedNonIncomingWork)
        monitor = CodexMonitorSnapshot(
            usage: monitor.usage,
            threads: reducedThreads,
            findings: monitor.findings,
            refreshedAt: monitor.refreshedAt,
            threadCounts: CodexThreadCounts(
                total: snapshot.threadCounts.total + retainedCounts.total,
                active: snapshot.threadCounts.active + retainedCounts.active,
                open: snapshot.threadCounts.open + retainedCounts.open,
                terminal: snapshot.threadCounts.terminal + retainedCounts.terminal
            )
        )

        return effects
    }

    /// 业务语义：realtime 事件是明确生命周期迁移的入口，terminal review 只能从这里或等价显式状态进入。
    @discardableResult
    public mutating func applyRealtimeEvent(_ event: CodexRealtimeEvent, now: Date) -> CodexFeatureEffects {
        switch event {
        case let .usage(usage):
            monitor = CodexMonitorSnapshot(
                usage: usage,
                threads: monitor.threads,
                findings: monitor.findings,
                refreshedAt: now,
                threadCounts: CodexThreadCounts.from(monitor.threads)
            )
            return .none
        case let .thread(thread):
            let effects = updateThread(
                id: thread.id,
                title: thread.title,
                status: thread.status,
                detail: thread.detail,
                now: thread.updatedAt
            )
            monitor.refreshedAt = now
            return effects
        case let .finding(finding):
            if let index = monitor.findings.firstIndex(where: { $0.id == finding.id }) {
                monitor.findings[index] = finding
            } else {
                monitor.findings.append(finding)
            }
            monitor.refreshedAt = now
            return .none
        }
    }

    /// 业务语义：统一应用单个 Codex 线程生命周期，并只对明确 terminal 迁移产生 review。
    @discardableResult
    public mutating func updateThread(
        id: String,
        title: String,
        status: CodexThreadStatus,
        detail: String,
        now: Date
    ) -> CodexFeatureEffects {
        let previousStatus = monitor.threads.first(where: { $0.id == id })?.status
        let updatedThread = CodexThreadSummary(id: id, title: title, status: status, detail: detail, updatedAt: now)

        if let index = monitor.threads.firstIndex(where: { $0.id == id }) {
            monitor.threads[index] = updatedThread
        } else {
            monitor.threads.insert(updatedThread, at: 0)
        }

        let reduced = CodexThreadLifecycleReducer.reduce(threads: monitor.threads)
        monitor.threads = reduced.visibleThreads
        monitor.threadCounts = reduced.counts

        if status.isNonTerminalWork {
            reviewItems.removeAll { $0.threadID == id }
        }

        guard previousStatus?.isNonTerminalWork == true, status.isTerminal else {
            return .none
        }

        let notification = NotificationRequest(
            title: status == .failed ? "Codex thread failed" : "Codex thread complete",
            body: "\(title): \(detail)",
            createdAt: now
        )
        upsertReviewItem(
            CodexReviewItem(
                threadID: id,
                title: title,
                status: status,
                detail: detail,
                createdAt: now
            )
        )
        return CodexFeatureEffects(
            notifications: [notification],
            activities: [
                CodexFeatureActivityEffect(
                    title: notification.title,
                    detail: notification.body,
                    date: now
                )
            ]
        )
    }

    /// 业务语义：用户确认某个 Codex 结果后，只清理 review attention，不改写线程历史。
    public mutating func acknowledgeReview(id: String) {
        reviewItems.removeAll { $0.id == id }
    }

    /// 业务语义：collapsed 快捷确认只处理最新待处理 Codex review。
    public mutating func acknowledgeLatestReview() {
        guard let review = reviewItems.first else {
            return
        }
        acknowledgeReview(id: review.id)
    }

    /// 业务语义：同一个线程只保留最新 review，避免重复完成事件堆叠成多个待处理项。
    private mutating func upsertReviewItem(_ item: CodexReviewItem) {
        if let index = reviewItems.firstIndex(where: { $0.threadID == item.threadID }) {
            reviewItems[index] = item
        } else {
            reviewItems.insert(item, at: 0)
        }

        reviewItems.sort { $0.createdAt > $1.createdAt }
        if reviewItems.count > 8 {
            reviewItems.removeLast(reviewItems.count - 8)
        }
    }
}
