import Foundation

public protocol CodexMonitorEventSink: AnyObject {
    func refreshCodexMonitor(_ snapshot: CodexMonitorSnapshot)
    func applyCodexRealtimeEvent(_ event: CodexRealtimeEvent)
    func applyCodexIntegrationFinding(_ finding: CodexIntegrationFinding)
}

extension TaskCoordinator: CodexMonitorEventSink {
    /// 业务语义：monitor service 交付 snapshot 时，coordinator 仅作为兼容 sink 转发给 CodexFeature。
    public func refreshCodexMonitor(_ snapshot: CodexMonitorSnapshot) {
        refreshCodexMonitor(snapshot, now: nil)
    }

    /// 业务语义：monitor service 交付 realtime event 时，coordinator 仅作为兼容 sink 转发给 CodexFeature。
    public func applyCodexRealtimeEvent(_ event: CodexRealtimeEvent) {
        applyCodexRealtimeEvent(event, now: nil)
    }

    /// 业务语义：兼容 coordinator 将 monitor service finding 转成 CodexFeature 可消费的 typed event。
    public func applyCodexIntegrationFinding(_ finding: CodexIntegrationFinding) {
        applyCodexRealtimeEvent(.finding(finding))
    }
}

public final class CodexMonitorService {
    private weak var sink: CodexMonitorEventSink?
    private let provider: CodexMonitorSnapshotProviding
    private let realtimeStream: CodexRealtimeEventStreaming?
    private let interval: TimeInterval
    private let onMonitorUpdated: (() -> Void)?
    private var timer: Timer?
    private var isRefreshing = false

    /// 业务语义：monitor service 只把 provider/stream 的 typed observation 交给 sink，不拥有 Codex feature state。
    public init(
        sink: CodexMonitorEventSink,
        provider: CodexMonitorSnapshotProviding = CodexCLIStatusProvider(),
        realtimeStream: CodexRealtimeEventStreaming? = ProcessCodexAppServerEventStream(),
        interval: TimeInterval = 120,
        onMonitorUpdated: (() -> Void)? = nil
    ) {
        self.sink = sink
        self.provider = provider
        self.realtimeStream = realtimeStream
        self.interval = interval
        self.onMonitorUpdated = onMonitorUpdated
    }

    /// 业务语义：首次 snapshot 建立线程基线后再接 realtime，避免两个 app-server stdio probe 并发抢启动状态。
    public func start() {
        refresh { [weak self] in
            self?.startRealtimeStream()
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 业务语义：停止 monitor 必须同时取消周期刷新和 realtime stream，避免过期观察写回状态。
    public func stop() {
        timer?.invalidate()
        timer = nil
        realtimeStream?.stop()
    }

    /// 业务语义：realtime stream 只传递 typed events/finding，状态解释交给 sink 后面的 CodexFeature。
    private func startRealtimeStream() {
        realtimeStream?.start(
            onEvent: { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    self?.sink?.applyCodexRealtimeEvent(event)
                    self?.onMonitorUpdated?()
                }
            },
            onFinished: { [weak self] finding in
                guard let finding else {
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.sink?.applyCodexIntegrationFinding(finding)
                    self?.onMonitorUpdated?()
                }
            }
        )
    }

    /// 业务语义：snapshot refresh 在后台读取 Codex 状态，完成后只在主线程发布 typed snapshot。
    private func refresh(completion: (() -> Void)? = nil) {
        guard !isRefreshing else {
            completion?()
            return
        }
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let snapshot = provider.loadSnapshot(now: Date())
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                sink?.refreshCodexMonitor(snapshot)
                isRefreshing = false
                onMonitorUpdated?()
                completion?()
            }
        }
    }
}
