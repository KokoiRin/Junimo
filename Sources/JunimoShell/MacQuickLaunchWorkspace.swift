import AppKit
import JunimoCore

// MacQuickLaunchWorkspace 是类型化快捷目标到 NSWorkspace 的唯一 macOS 副作用边界。
final class MacQuickLaunchWorkspace: QuickLaunchOpening {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openApplication(bundleIdentifier: String) -> Bool {
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        workspace.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    @MainActor
    func activateApplication(bundleIdentifier: String) async throws {
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw AppShortcutError.message("找不到此应用，请重新安装或从收藏中移除。")
        }
        // 前台应用也可能没有可见窗口，统一走系统 reopen 流程恢复或重新打开窗口。
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func openURL(_ url: URL) -> Bool {
        workspace.open(url)
    }
}
