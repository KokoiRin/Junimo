import Combine
import Foundation

@MainActor
public final class ShellState: ObservableObject {
    @Published public private(set) var isExpanded = false
    @Published public private(set) var surfaceState = SurfaceState()
    public private(set) var hoverExpansionEnabled: Bool

    public var expansionDidChange: ((Bool) -> Void)?

    private let backend: ShellBackendClient
    private let defaults: UserDefaults
    private static let hoverExpansionKey = "notch.hoverExpansionEnabled"
    private var refreshTask: Task<Void, Never>?
    private var latestRevision: UInt64?

    public init(backend: ShellBackendClient = GoBackendClient(), defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        hoverExpansionEnabled = defaults.object(forKey: Self.hoverExpansionKey) as? Bool ?? true
    }

    deinit {
        refreshTask?.cancel()
        backend.stop()
    }

    public func start() {
        refreshTask?.cancel()
        latestRevision = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.start()
                accept(try await backend.loadState())
                await pollBackend()
            } catch {
                // 保留 loading 或最后成功快照；下一次 start 会重新建立连接。
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        backend.stop()
    }

    public func pointerEntered() {
        guard hoverExpansionEnabled else { return }
        expand()
    }

    public func expand() {
        setExpanded(true)
    }

    public func toggleHoverExpansion() {
        hoverExpansionEnabled.toggle()
        defaults.set(hoverExpansionEnabled, forKey: Self.hoverExpansionKey)
        if !hoverExpansionEnabled { setExpanded(false) }
    }

    public func pointerExited() {
        setExpanded(false)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        expansionDidChange?(expanded)
    }

    private func pollBackend() async {
        while !Task.isCancelled {
            do {
                accept(try await backend.loadState())
            } catch {
                if !Task.isCancelled, surfaceState.activity.isWorking == true {
                    surfaceState.activity.isWorking = nil
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // accept 只接受严格更新的 Go 快照，防止网络乱序使活动或用量倒退。
    private func accept(_ snapshot: SurfaceState) {
        if let latestRevision, snapshot.revision <= latestRevision {
            return
        }
        latestRevision = snapshot.revision
        surfaceState = snapshot
    }
}
