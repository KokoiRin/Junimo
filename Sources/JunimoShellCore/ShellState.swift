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
    private let pollIntervalNanoseconds: UInt64
    private let retryDelayNanoseconds: UInt64
    private static let hoverExpansionKey = "notch.hoverExpansionEnabled"
    private var refreshTask: Task<Void, Never>?
    private var latestRevision: UInt64?

    public init(
        backend: ShellBackendClient = GoBackendClient(),
        defaults: UserDefaults = .standard,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.backend = backend
        self.defaults = defaults
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.retryDelayNanoseconds = retryDelayNanoseconds
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
            await self.runLifecycle()
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

    // 后端启动失败或运行中途退出时按退避间隔自动重连，避免外壳永久停留在 loading 或失联状态。
    private func runLifecycle() async {
        var connected = false
        var retryDelay = retryDelayNanoseconds
        let maxRetryDelay = max(retryDelayNanoseconds, 15_000_000_000)

        while !Task.isCancelled {
            if !connected {
                do {
                    try await backend.start()
                    connected = true
                    latestRevision = nil
                    retryDelay = retryDelayNanoseconds
                } catch {
                    guard !Task.isCancelled else { return }
                    clearTransientWorkingState()
                    try? await Task.sleep(nanoseconds: retryDelay)
                    retryDelay = min(retryDelay * 2, maxRetryDelay)
                    continue
                }
            }

            do {
                accept(try await backend.loadState())
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            } catch {
                guard !Task.isCancelled else { return }
                clearTransientWorkingState()
                if shouldRestartBackend(after: error) {
                    backend.stop()
                    connected = false
                    latestRevision = nil
                    try? await Task.sleep(nanoseconds: retryDelay)
                    retryDelay = min(retryDelay * 2, maxRetryDelay)
                } else {
                    try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                }
            }
        }
    }

    private func clearTransientWorkingState() {
        if surfaceState.activity.isWorking == true { surfaceState.activity.isWorking = nil }
        if surfaceState.antigravity?.isAppRunning != nil { surfaceState.antigravity?.isAppRunning = nil }
        if surfaceState.antigravity?.isWorking != nil { surfaceState.antigravity?.isWorking = nil }
    }

    private func shouldRestartBackend(after error: Error) -> Bool {
        guard let backendError = error as? BackendError else { return false }
        return backendError == .backendExited || backendError == .instanceMismatch
    }

    // accept 只接受严格更新的 Go 快照，且在业务载荷未变时不重复发布，避免每秒触发无效 SwiftUI 重绘。
    private func accept(_ snapshot: SurfaceState) {
        if let latestRevision, snapshot.revision <= latestRevision {
            return
        }
        let isFirstForSession = (latestRevision == nil)
        latestRevision = snapshot.revision
        if !isFirstForSession && surfaceState.hasSamePayload(as: snapshot) {
            return
        }
        surfaceState = snapshot
    }
}
