import Combine
import Foundation

public struct AppShortcut: Codable, Equatable, Identifiable {
    public var bundleId: String
    public var name: String
    public var id: String { bundleId }
    public init(bundleId: String, name: String) { self.bundleId = bundleId; self.name = name }
}

public struct AppShortcutList: Codable, Equatable {
    public var items: [AppShortcut]
    public var revision: UInt64
    public init(items: [AppShortcut], revision: UInt64 = 1) { self.items = items; self.revision = revision }
}

public enum AppShortcutError: LocalizedError {
    case message(String)
    case conflict
    public var errorDescription: String? {
        if case let .message(message) = self { return message }
        return "收藏已在其他地方更新，请查看最新列表后重新操作。"
    }
}

public protocol AppShortcutsBackend: AnyObject {
    func loadAppShortcuts() async throws -> AppShortcutList
    func saveAppShortcuts(_ items: [AppShortcut], revision: UInt64) async throws -> AppShortcutList
}

// 列表只在后端确认后发布；界面不自行推断保存成功或覆盖失败前的收藏。
@MainActor
public final class AppShortcutsStore: ObservableObject {
    @Published public private(set) var items: [AppShortcut] = []
    @Published public private(set) var revision: UInt64 = 0
    @Published public private(set) var isLoaded = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var error: String?
    private let backend: AppShortcutsBackend
    private var loadTask: Task<Void, Never>?
    private var hasLoadError = false
    private let refreshInterval: UInt64

    public init(backend: AppShortcutsBackend, refreshIntervalNanoseconds: UInt64 = 1_000_000_000) {
        self.backend = backend
        self.refreshInterval = refreshIntervalNanoseconds
    }
    public func start() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !isSaving {
                    do {
                        let value = try await backend.loadAppShortcuts()
                        guard !Task.isCancelled else { return }
                        if !isSaving {
                            accept(value)
                            if hasLoadError { error = nil; hasLoadError = false }
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        if !isSaving && (self.error == nil || hasLoadError) {
                            self.error = "读取常用应用失败：\(error.localizedDescription)"
                            hasLoadError = true
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: refreshInterval)
            }
        }
    }
    public func stop() { loadTask?.cancel(); loadTask = nil }
    public func save(_ proposed: [AppShortcut], basedOn revision: UInt64) async {
        guard isLoaded, !isSaving else { return }
        isSaving = true
        hasLoadError = false
        defer { isSaving = false }
        do {
            accept(try await backend.saveAppShortcuts(proposed, revision: revision))
            error = nil
        } catch AppShortcutError.conflict {
            // 冲突不自动重放整表覆盖；重新读取后让用户按最新列表确认操作。
            if let latest = try? await backend.loadAppShortcuts() { accept(latest) }
            error = AppShortcutError.conflict.localizedDescription
        } catch { self.error = error.localizedDescription }
    }

    private func accept(_ value: AppShortcutList) {
        guard value.revision >= revision else { return }
        if items != value.items { items = value.items }
        revision = value.revision
        isLoaded = true
    }
}

public enum AppBarPlacement: String, CaseIterable {
    case right, below
    public var title: String { self == .right ? "刘海右侧" : "刘海下方" }
    public var cellSize: CGFloat { self == .right ? 30 : 36 }
    public var iconSize: CGFloat { cellSize - 4 }
    public var limit: Int { self == .right ? 4 : 6 }
}

// 几何策略只计算可显示槽位；收藏顺序和数量校验由后端负责。
public struct AppBarCapacity: Equatable {
    public let visibleCount: Int
    public let hasOverflow: Bool
    public let width: CGFloat
    public init(count: Int, placement: AppBarPlacement, availableWidth: CGFloat) {
        let slots = max(0, Int((availableWidth - 8) / placement.cellSize))
        let capacity = min(placement.limit, slots)
        hasOverflow = count > capacity && slots > 0
        visibleCount = hasOverflow ? min(placement.limit, max(0, slots - 1), max(0, count - 1)) : min(count, capacity)
        width = CGFloat(visibleCount + (hasOverflow ? 1 : 0)) * placement.cellSize + (slots > 0 && count > 0 ? 8 : 0)
    }
}
