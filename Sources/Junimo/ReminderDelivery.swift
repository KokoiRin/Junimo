import Combine
import Foundation
import JunimoCore
import UserNotifications

protocol ReminderDelivering {
    func deliver(_ request: NotificationRequest)
}

final class ReminderDeliveryBridge {
    private var cancellable: AnyCancellable?
    private var deliveredIDs = Set<UUID>()

    /// 业务语义：通知投递后延迟确认，避免 @Published willSet 重入覆盖 pending 队列清理。
    init(coordinator: TaskCoordinator, adapter: ReminderDelivering) {
        cancellable = coordinator.$pendingNotifications.sink { [weak self, weak coordinator] requests in
            guard let self else { return }
            for request in requests where !deliveredIDs.contains(request.id) {
                deliveredIDs.insert(request.id)
                adapter.deliver(request)
                DispatchQueue.main.async {
                    coordinator?.markNotificationDelivered(id: request.id)
                }
            }
        }
    }
}

final class UserNotificationReminderAdapter: ReminderDelivering {
    private let center = UNUserNotificationCenter.current()

    func deliver(_ request: NotificationRequest) {
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, _ in
            guard granted else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let notification = UNNotificationRequest(
                identifier: request.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.add(notification)
        }
    }
}
