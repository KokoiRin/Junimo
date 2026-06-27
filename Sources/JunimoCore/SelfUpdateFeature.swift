import Foundation

public struct SelfUpdateFeature {
    public private(set) var snapshot: SelfUpdateSnapshot

    public init(currentVersion: ReleaseVersion) {
        self.snapshot = SelfUpdateSnapshot(currentVersion: currentVersion)
    }

    /// 业务语义：检查开始只进入 checking，不改变已有 latest 版本判断。
    public mutating func startChecking(now: Date) {
        snapshot.state = .checking
        snapshot.message = "Checking for updates..."
        snapshot.lastCheckedAt = now
    }

    /// 业务语义：release 检查结果是唯一能把版本状态推到 available/up-to-date/failure 的入口。
    public mutating func applyReleaseCheck(_ result: SelfUpdateCheckResult, now: Date) {
        snapshot.lastCheckedAt = now
        switch result {
        case let .success(info):
            snapshot.latestVersion = info.version
            if info.version > snapshot.currentVersion {
                snapshot.state = .updateAvailable
                snapshot.message = "Install Junimo \(info.version)"
            } else {
                snapshot.state = .upToDate
                snapshot.message = "Junimo is up to date"
            }
        case let .failure(message):
            snapshot.state = .checkFailed
            snapshot.message = message
        }
    }

    /// 业务语义：安装只能从已发现新版本状态进入，防止同版本或检查失败后误触发更新。
    public mutating func startInstalling(now: Date) {
        guard snapshot.state == .updateAvailable else { return }
        snapshot.state = .installing
        snapshot.message = "Installing update..."
        snapshot.lastCheckedAt = now
    }

    /// 业务语义：外部 updater 启动失败必须回到可见失败状态，用户才能重试。
    public mutating func applyInstallFailure(message: String, now: Date) {
        snapshot.state = .installFailed
        snapshot.message = message
        snapshot.lastCheckedAt = now
    }
}
