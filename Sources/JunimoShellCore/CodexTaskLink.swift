import Foundation

// CodexTaskLink 集中保存 Junimo 与 Codex macOS 应用之间的稳定跳转契约。
public enum CodexTaskLink {
    public static let bundleIdentifier = "com.openai.codex"

    public static func url(threadID: String) -> URL? {
        guard UUID(uuidString: threadID) != nil else { return nil }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(threadID)"
        return components.url
    }
}
