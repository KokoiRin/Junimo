import Foundation

// QuickLaunchDestination 是可执行目标的封闭集合，配置只能声明网页或 macOS 应用。
public enum QuickLaunchDestination: Equatable {
    case application(bundleIdentifier: String)
    case website(URL)
}

// QuickLaunchCommand 是视图和启动器共享的已校验入口，不暴露配置解析细节。
public struct QuickLaunchCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let destination: QuickLaunchDestination

    public init(id: String, title: String, systemImage: String, destination: QuickLaunchDestination) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.destination = destination
    }
}

// QuickLaunchIconPreset 提供配置文件可直接选择的稳定图标名，避免用户记忆 SF Symbols 名称。
public enum QuickLaunchIconPreset: String, CaseIterable, Codable, Equatable {
    case app
    case code
    case website
    case reading
    case document
    case tools
    case data
    case video
    case music
    case ai
    case link

    public var systemImage: String {
        switch self {
        case .app: return "app.fill"
        case .code: return "terminal.fill"
        case .website: return "globe"
        case .reading: return "book.pages.fill"
        case .document: return "doc.text.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .data: return "chart.bar.fill"
        case .video: return "play.rectangle.fill"
        case .music: return "music.note"
        case .ai: return "sparkles"
        case .link: return "link"
        }
    }
}

public enum QuickLaunchTargetType: String, Codable, Equatable {
    case application
    case url
}

// QuickLaunchItemConfiguration 是用户编辑的单个 JSON 入口。
public struct QuickLaunchItemConfiguration: Codable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let type: QuickLaunchTargetType
    public let target: String

    public init(id: String, title: String, icon: String, type: QuickLaunchTargetType, target: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.type = type
        self.target = target
    }
}

// QuickLaunchConfiguration 用 version 固定外部文件契约，后续格式升级不会静默误读旧文件。
public struct QuickLaunchConfiguration: Codable, Equatable {
    public let version: Int
    public let iconOptions: [String]?
    public let items: [QuickLaunchItemConfiguration]

    public init(
        version: Int = 1,
        iconOptions: [String]? = QuickLaunchIconPreset.allCases.map(\.rawValue),
        items: [QuickLaunchItemConfiguration]
    ) {
        self.version = version
        self.iconOptions = iconOptions
        self.items = items
    }
}

public enum QuickLaunchConfigurationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case emptyCatalog
    case tooManyItems(Int)
    case invalidID(String)
    case duplicateID(String)
    case emptyTitle(String)
    case unknownIcon(String)
    case invalidApplicationTarget(String)
    case invalidURLTarget(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "不支持 quick-launch.json 版本 \(version)"
        case .emptyCatalog:
            return "快捷入口至少需要保留一项"
        case let .tooManyItems(count):
            return "快捷入口最多支持 12 项，当前有 \(count) 项"
        case let .invalidID(id):
            return "快捷入口 id 无效：\(id)"
        case let .duplicateID(id):
            return "快捷入口 id 重复：\(id)"
        case let .emptyTitle(id):
            return "快捷入口标题为空：\(id)"
        case let .unknownIcon(icon):
            return "未知图标类型：\(icon)"
        case let .invalidApplicationTarget(target):
            return "应用 Bundle ID 无效：\(target)"
        case let .invalidURLTarget(target):
            return "网页地址无效：\(target)"
        }
    }
}

// QuickLaunchCatalog 集中默认值、JSON 编解码和校验；调用者只消费已验证的 Commands。
public enum QuickLaunchCatalog {
    public static let defaultConfiguration = QuickLaunchConfiguration(items: [
        QuickLaunchItemConfiguration(
            id: "codex",
            title: "Codex",
            icon: QuickLaunchIconPreset.code.rawValue,
            type: .application,
            target: "com.openai.codex"
        )
    ])

    public static let commands: [QuickLaunchCommand] = {
        // 默认配置属于源码不变量；若失效应在测试和开发阶段立即暴露。
        try! commands(from: defaultConfiguration)
    }()

    public static func decode(_ data: Data) throws -> [QuickLaunchCommand] {
        try commands(from: JSONDecoder().decode(QuickLaunchConfiguration.self, from: data))
    }

    public static func encode(_ configuration: QuickLaunchConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration)
    }

    public static func commands(from configuration: QuickLaunchConfiguration) throws -> [QuickLaunchCommand] {
        guard configuration.version == 1 else {
            throw QuickLaunchConfigurationError.unsupportedVersion(configuration.version)
        }
        guard !configuration.items.isEmpty else {
            throw QuickLaunchConfigurationError.emptyCatalog
        }
        guard configuration.items.count <= 12 else {
            throw QuickLaunchConfigurationError.tooManyItems(configuration.items.count)
        }

        var seenIDs = Set<String>()
        return try configuration.items.map { item in
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = item.target.trimmingCharacters(in: .whitespacesAndNewlines)

            guard isValidID(id) else {
                throw QuickLaunchConfigurationError.invalidID(item.id)
            }
            guard seenIDs.insert(id).inserted else {
                throw QuickLaunchConfigurationError.duplicateID(id)
            }
            guard !title.isEmpty else {
                throw QuickLaunchConfigurationError.emptyTitle(id)
            }
            guard let icon = QuickLaunchIconPreset(rawValue: item.icon) else {
                throw QuickLaunchConfigurationError.unknownIcon(item.icon)
            }

            let destination: QuickLaunchDestination
            switch item.type {
            case .application:
                guard isValidBundleIdentifier(target) else {
                    throw QuickLaunchConfigurationError.invalidApplicationTarget(target)
                }
                destination = .application(bundleIdentifier: target)
            case .url:
                guard let url = validWebURL(target) else {
                    throw QuickLaunchConfigurationError.invalidURLTarget(target)
                }
                destination = .website(url)
            }

            return QuickLaunchCommand(
                id: id,
                title: title,
                systemImage: icon.systemImage,
                destination: destination
            )
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 40 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validWebURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

// QuickLaunchOpening 是启动副作用的 seam，生产和测试分别提供 macOS 与记录型适配器。
public protocol QuickLaunchOpening: AnyObject {
    func openApplication(bundleIdentifier: String) -> Bool
    func openURL(_ url: URL) -> Bool
}

// QuickLauncher 执行 Command，并把目标类型路由细节隐藏在单一 module 内。
public struct QuickLauncher {
    private let workspace: QuickLaunchOpening

    public init(workspace: QuickLaunchOpening) {
        self.workspace = workspace
    }

    @discardableResult
    public func open(_ command: QuickLaunchCommand) -> Bool {
        switch command.destination {
        case let .application(bundleIdentifier):
            return workspace.openApplication(bundleIdentifier: bundleIdentifier)
        case let .website(url):
            return workspace.openURL(url)
        }
    }
}
