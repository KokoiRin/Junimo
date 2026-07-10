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

    public init(backend: ShellBackendClient = GoBackendClient()) {
        self.backend = backend
    }

    deinit {
        refreshTask?.cancel()
        backend.stop()
    }

    public func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.start()
                backendMessage = "Connected"
                surfaceState = try await backend.loadState()
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
            await applyIntent(BackendIntent(type: "pomodoro.startFocus", durationSeconds: durationSeconds))
        }
    }

    public func pausePomodoro() {
        Task {
            await applyIntent(BackendIntent(type: "pomodoro.pause"))
        }
    }

    public func resumePomodoro() {
        Task {
            await applyIntent(BackendIntent(type: "pomodoro.resume"))
        }
    }

    public func resetPomodoro() {
        Task {
            await applyIntent(BackendIntent(type: "pomodoro.reset"))
        }
    }

    public func startBreak() {
        Task {
            await applyIntent(BackendIntent(type: "pomodoro.startBreak"))
        }
    }

    public func skipBreak() {
        Task {
            await applyIntent(BackendIntent(type: "pomodoro.skipBreak"))
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        expansionDidChange?(expanded)
    }

    private func applyIntent(_ intent: BackendIntent) async {
        do {
            surfaceState = try await backend.sendIntent(intent)
            backendMessage = "Connected"
        } catch {
            backendMessage = "Backend unavailable"
        }
    }

    private func pollBackend() async {
        while !Task.isCancelled {
            do {
                surfaceState = try await backend.loadState()
                backendMessage = "Connected"
            } catch {
                backendMessage = "Backend unavailable"
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
