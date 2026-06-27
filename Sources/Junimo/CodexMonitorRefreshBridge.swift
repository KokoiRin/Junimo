import Foundation
import JunimoCore

final class CodexMonitorRefreshBridge {
    private let service: CodexMonitorService

    init(
        coordinator: TaskCoordinator,
        provider: CodexMonitorSnapshotProviding = CodexCLIStatusProvider(),
        realtimeStream: CodexRealtimeEventStreaming? = ProcessCodexAppServerEventStream(),
        interval: TimeInterval = 120,
        onMonitorUpdated: (() -> Void)? = nil
    ) {
        self.service = CodexMonitorService(
            sink: coordinator,
            provider: provider,
            realtimeStream: realtimeStream,
            interval: interval,
            onMonitorUpdated: onMonitorUpdated
        )
    }

    /// 业务语义：app shell bridge 只启动 core monitor service，不直接解释 Codex 协议。
    func start() {
        service.start()
    }

    /// 业务语义：app shell bridge 停止 monitor service，避免生命周期逻辑散在 AppKit 层。
    func stop() {
        service.stop()
    }
}
