import Foundation

public struct NotificationOutbox {
    public private(set) var pending: [NotificationRequest]

    /// 业务语义：NotificationOutbox 是待投递系统通知请求的 Swift core 权威队列。
    public init(pending: [NotificationRequest] = []) {
        self.pending = pending
    }

    /// 业务语义：单个通知请求按 feature 产生顺序进入待投递队列。
    public mutating func enqueue(_ request: NotificationRequest) {
        pending.append(request)
    }

    /// 业务语义：批量通知请求保留输入顺序，方便 app shell 顺序投递。
    public mutating func enqueue(contentsOf requests: [NotificationRequest]) {
        pending.append(contentsOf: requests)
    }

    /// 业务语义：app shell 确认投递后只移除匹配请求，未知 ID 不影响队列。
    public mutating func markDelivered(id: UUID) {
        pending.removeAll { $0.id == id }
    }
}
