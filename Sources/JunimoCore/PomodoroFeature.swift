import Foundation

public struct PomodoroFeatureEffects: Equatable {
    public var notifications: [NotificationRequest]

    public init(notifications: [NotificationRequest] = []) {
        self.notifications = notifications
    }

    public var isEmpty: Bool {
        notifications.isEmpty
    }
}

public struct PomodoroFeature {
    public private(set) var activePomodoro: PomodoroSession?

    private let core: PomodoroCore & ConsoleStateCore

    /// 业务语义：PomodoroFeature 只拥有 Swift 投影和 completion effect，timer 权威仍来自 core。
    public init(core: PomodoroCore & ConsoleStateCore) {
        self.core = core
        self.activePomodoro = core.activePomodoro()
    }

    /// 业务语义：启动 Pomodoro 后刷新 feature 投影，让 UI 读取同一个 active timer 视图。
    public mutating func start(duration: TimeInterval, now: Date) {
        core.start(duration: duration, at: now)
        refreshProjection()
    }

    /// 业务语义：取消 Pomodoro 后只同步投影，取消活动记录仍由 core 生命周期负责。
    @discardableResult
    public mutating func cancel(now: Date) -> Bool {
        let result = core.cancel(at: now)
        if result.changed {
            refreshProjection()
        }
        return result.changed
    }

    /// 业务语义：完成时将 core completion 转成通知 effect，未完成时不产生 Swift 副作用。
    public mutating func advanceTime(to date: Date) -> PomodoroFeatureEffects {
        let result = core.advanceTime(to: date)
        guard result.completed else {
            refreshProjection()
            return PomodoroFeatureEffects()
        }

        refreshProjection()
        let notification = NotificationRequest(
            title: result.notificationTitle,
            body: result.notificationBody,
            createdAt: date
        )
        return PomodoroFeatureEffects(notifications: [notification])
    }

    /// 业务语义：active timer projection 只从 core 刷新，避免 Swift 侧复制 timer 规则。
    private mutating func refreshProjection() {
        activePomodoro = core.activePomodoro()
    }
}
