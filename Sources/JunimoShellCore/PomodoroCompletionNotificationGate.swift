public struct PomodoroCompletionNotificationGate {
    // isInitialized 区分首次连接基线与连接后新到达的事件。
    private var isInitialized = false
    // lastEventID 记录已观察的最新 Go 完成事件，不推断番茄钟状态转换。
    private var lastEventID: UInt64?

    public init() {}

    // observe 对新事件 ID 返回需投递的模式，首次快照只建立基线，重复或旧事件均忽略。
    public mutating func observe(_ event: PomodoroCompletionEvent?) -> PomodoroMode? {
        guard isInitialized else {
            isInitialized = true
            lastEventID = event?.id
            return nil
        }
        guard let event else { return nil }
        if let lastEventID, event.id <= lastEventID {
            return nil
        }
        lastEventID = event.id
        return event.mode
    }
}
