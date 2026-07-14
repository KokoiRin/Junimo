import Combine
import Foundation

@MainActor
public final class ShellState: ObservableObject {
    @Published public private(set) var isExpanded = false
    @Published public private(set) var surfaceState = SurfaceState()
    @Published public private(set) var backendMessage = "Starting"

    public var expansionDidChange: ((Bool) -> Void)?

    private let backend: ShellBackendClient
    private var refreshTask: Task<Void, Never>?
    // latestRevision 记录已渲染的最新 Go 快照序号，使轮询与意图响应可以安全乱序到达。
    private var latestRevision: UInt64?

    public init(backend: ShellBackendClient = GoBackendClient()) {
        self.backend = backend
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
                backendMessage = "Connected"
                accept(try await backend.loadState())
                await pollBackend()
            } catch {
                backendMessage = "Backend unavailable"
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        backend.stop()
    }

    public func pointerEntered() {
        setExpanded(true)
    }

    public func pointerExited() {
        setExpanded(false)
    }

    public func startFocus(durationSeconds: Int = 25 * 60) {
        Task {
            await applyIntent(.startFocus(durationSeconds: durationSeconds))
        }
    }

    public func pausePomodoro() {
        Task {
            await applyIntent(.pause)
        }
    }

    public func resumePomodoro() {
        Task {
            await applyIntent(.resume)
        }
    }

    public func resetPomodoro() {
        Task {
            await applyIntent(.reset)
        }
    }

    public func startBreak() {
        Task {
            await applyIntent(.startBreak)
        }
    }

    public func skipBreak() {
        Task {
            await applyIntent(.skipBreak)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        expansionDidChange?(expanded)
    }

    private func applyIntent(_ intent: PomodoroIntent) async {
        do {
            accept(try await backend.sendIntent(intent))
            backendMessage = "Connected"
        } catch {
            backendMessage = "Backend unavailable"
        }
    }

    private func pollBackend() async {
        while !Task.isCancelled {
            do {
                accept(try await backend.loadState())
                backendMessage = "Connected"
            } catch {
                backendMessage = "Backend unavailable"
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // accept 只接受首份或 revision 严格更大的 Go 快照，相等与更旧响应均不得覆盖 UI。
    private func accept(_ snapshot: SurfaceState) {
        if let latestRevision, snapshot.revision <= latestRevision {
            return
        }
        latestRevision = snapshot.revision
        surfaceState = snapshot
    }
}
