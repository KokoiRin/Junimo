import Foundation

// CodexCompletionNotificationGate 用稳定 turn ID 阻止同一后端事件被重复轮询投递。
public struct CodexCompletionNotificationGate {
    private var lastObservedEventID: String?

    public init() {}

    // 历史任务基线由 Go 负责；Swift 收到第一个真实完成事件时应立即投递。
    public mutating func observe(_ event: CodexCompletionEvent?) -> CodexCompletionEvent? {
        guard let event, event.id != lastObservedEventID else {
            return nil
        }
        lastObservedEventID = event.id
        return event
    }
}

// AntigravityCompletionNotificationGate 使用有界集合对 Antigravity 完成事件去重，避免在 AppKit 壳层维护线性数组。
public struct AntigravityCompletionNotificationGate {
    private let capacity: Int
    private var seenOrder: [String] = []
    private var seenSet: Set<String> = []

    public init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    public mutating func observe(_ events: [AntigravityCompletion]?) -> [AntigravityCompletion] {
        guard let events, !events.isEmpty else { return [] }
        var fresh: [AntigravityCompletion] = []
        for event in events where seenSet.insert(event.id).inserted {
            seenOrder.append(event.id)
            fresh.append(event)
        }
        if seenOrder.count > capacity {
            let overflow = seenOrder.count - capacity
            for removed in seenOrder.prefix(overflow) {
                seenSet.remove(removed)
            }
            seenOrder.removeFirst(overflow)
        }
        return fresh
    }
}
