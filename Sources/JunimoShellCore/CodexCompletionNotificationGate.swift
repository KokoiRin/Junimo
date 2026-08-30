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
