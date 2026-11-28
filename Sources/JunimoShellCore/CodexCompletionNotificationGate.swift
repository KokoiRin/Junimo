import Foundation

private struct DeliveredEventIDs {
    let capacity: Int
    private var order: [String] = []
    private var ids: Set<String> = []

    init(capacity: Int = 512) { self.capacity = max(1, capacity) }

    mutating func record(_ id: String) -> Bool {
        guard ids.insert(id).inserted else { return false }
        order.append(id)
        return true
    }

    mutating func trim() {
        let overflow = order.count - capacity
        guard overflow > 0 else { return }
        for id in order.prefix(overflow) { ids.remove(id) }
        order.removeFirst(overflow)
    }
}

public struct CodexCompletionNotificationGate {
    private var delivered = DeliveredEventIDs()

    public init() {}

    public mutating func observe(_ event: CodexCompletionEvent?, now: Int64 = Int64(Date().timeIntervalSince1970)) -> CodexCompletionEvent? {
        guard let event, event.canNotify(at: now), delivered.record(event.id) else { return nil }
        delivered.trim()
        return event
    }
}

public struct AntigravityCompletionNotificationGate {
    private var delivered: DeliveredEventIDs

    public init(capacity: Int = 512) { delivered = DeliveredEventIDs(capacity: capacity) }

    public mutating func observe(_ events: [AntigravityCompletion]?) -> [AntigravityCompletion] {
        let fresh = events?.filter { delivered.record($0.id) } ?? []
        delivered.trim()
        return fresh
    }
}
