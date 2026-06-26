import Foundation
import JunimoCore

final class CodexMonitorRefreshBridge {
    private weak var coordinator: TaskCoordinator?
    private let provider: CodexCLIStatusProvider
    private let interval: TimeInterval
    private var timer: Timer?
    private var isRefreshing = false

    init(
        coordinator: TaskCoordinator,
        provider: CodexCLIStatusProvider = CodexCLIStatusProvider(),
        interval: TimeInterval = 120
    ) {
        self.coordinator = coordinator
        self.provider = provider
        self.interval = interval
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let snapshot = provider.loadSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                coordinator?.refreshCodexMonitor(snapshot)
                isRefreshing = false
            }
        }
    }
}
