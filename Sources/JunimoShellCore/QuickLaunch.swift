import Foundation

// QuickLaunchCategory 是面板使用的稳定分类；具体入口无需重复声明自己的分类。
public enum QuickLaunchCategory: String, CaseIterable, Identifiable, Equatable {
    case application
    case website

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .application: return "应用"
        case .website: return "网页"
        }
    }
}

// QuickLaunchDestination 是可执行目标的封闭集合，分类由目标类型唯一派生。
public enum QuickLaunchDestination: Equatable {
    case application(bundleIdentifier: String)
    case website(URL)

    public var category: QuickLaunchCategory {
        switch self {
        case .application: return .application
        case .website: return .website
        }
    }
}

// QuickLaunchCommand 封装一个快捷入口的呈现信息和执行意图。
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

public struct QuickLaunchSection: Identifiable, Equatable {
    public let category: QuickLaunchCategory
    public let commands: [QuickLaunchCommand]

    public var id: QuickLaunchCategory { category }
}

// QuickLaunchCatalog 是快捷入口的唯一登记处，并按目标类型生成稳定分组。
public enum QuickLaunchCatalog {
    public static let commands: [QuickLaunchCommand] = [
        QuickLaunchCommand(
            id: "codex",
            title: "Codex",
            systemImage: "terminal.fill",
            destination: .application(bundleIdentifier: "com.openai.codex")
        ),
        QuickLaunchCommand(
            id: "rin",
            title: "RIN",
            systemImage: "book.pages.fill",
            destination: .website(URL(string: "https://kokoirin.github.io/rin3/")!)
        )
    ]

    public static var sections: [QuickLaunchSection] {
        QuickLaunchCategory.allCases.compactMap { category in
            let commands = commands.filter { $0.destination.category == category }
            return commands.isEmpty ? nil : QuickLaunchSection(category: category, commands: commands)
        }
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
