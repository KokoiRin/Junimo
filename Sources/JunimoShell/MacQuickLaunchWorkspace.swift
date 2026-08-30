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

    func openURL(_ url: URL) -> Bool {
        workspace.open(url)
    }
}
