import Foundation

public struct CodexThreadLifecycleReduction: Equatable {
    public var visibleThreads: [CodexThreadSummary]
    public var counts: CodexThreadCounts

    public init(visibleThreads: [CodexThreadSummary], counts: CodexThreadCounts) {
        self.visibleThreads = visibleThreads
        self.counts = counts
    }
}

public enum CodexThreadLifecycleReducer {
    public static let visibleThreadLimit = 8

    /// 业务语义：先用完整线程集合计算生命周期计数，再截断成刘海可展示列表。
    public static func reduce(threads: [CodexThreadSummary], visibleLimit: Int = visibleThreadLimit) -> CodexThreadLifecycleReduction {
        let deduped = deduplicate(threads)
        let sorted = deduped.sorted { lhs, rhs in
            let lhsPriority = displayPriority(for: lhs.status)
            let rhsPriority = displayPriority(for: rhs.status)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        return CodexThreadLifecycleReduction(
            visibleThreads: Array(sorted.prefix(visibleLimit)),
            counts: CodexThreadCounts.from(deduped)
        )
    }

    /// 业务语义：同一 Codex 线程只能保留最新一条 source observation 作为生命周期权威。
    private static func deduplicate(_ threads: [CodexThreadSummary]) -> [CodexThreadSummary] {
        var byID: [String: CodexThreadSummary] = [:]
        for thread in threads {
            guard let existing = byID[thread.id] else {
                byID[thread.id] = thread
                continue
            }
            if thread.updatedAt >= existing.updatedAt {
                byID[thread.id] = thread
            }
        }
        return Array(byID.values)
    }

    /// 业务语义：open work 必须排在普通历史线程前，避免被展示截断隐藏。
    private static func displayPriority(for status: CodexThreadStatus) -> Int {
        switch status {
        case .waiting:
            return 0
        case .running:
            return 1
        case .open:
            return 2
        case .failed:
            return 3
        case .completed:
            return 4
        case .idle:
            return 5
        }
    }
}
