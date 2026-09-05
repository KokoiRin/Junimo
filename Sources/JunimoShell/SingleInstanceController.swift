import AppKit
import JunimoCore

@MainActor
final class SingleInstanceController: NSObject {
    private static let reopenNotification = Notification.Name("local.junimo.shell.reopen")
    private let userIdentity = String(getuid())
    private let lock: AppInstanceLock
    private let reopen: () -> Void

    init(reopen: @escaping () -> Void) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        lock = AppInstanceLock(fileURL: support.appendingPathComponent("Junimo/shell.lock"))
        self.reopen = reopen
        super.init()
        // 先注册再抢锁，让另一份 App 在首个实例尚未完成界面初始化时也能递交展开请求。
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveReopen),
            name: Self.reopenNotification,
            object: userIdentity,
            suspensionBehavior: .deliverImmediately
        )
    }

    func acquireOrReopen() throws -> Bool {
        guard try lock.acquire() else {
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenNotification, object: userIdentity, userInfo: nil, deliverImmediately: true
            )
            return false
        }
        return true
    }

    @objc private func receiveReopen(_ notification: Notification) {
        reopen()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
