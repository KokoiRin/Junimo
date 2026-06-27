import Foundation
import JunimoCore

struct PanelDiagnostics {
    var isVisible: Bool
    var isFloatingPanel: Bool
    var level: Int
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var screenMaxY: Double
}

final class LaunchHealthReporter {
    private let healthPath: String
    private let errorPath: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        healthPath = environment["JUNIMO_HEALTH_PATH"] ?? "/tmp/junimo-health.json"
        errorPath = "\(healthPath).error"
    }

    func write(coordinator: TaskCoordinator, panel: PanelDiagnostics) {
        let payload: [String: Any] = [
            "status": "ok",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "executablePath": Bundle.main.executablePath ?? "",
            "bundlePath": Bundle.main.bundlePath,
            "panel": [
                "visible": panel.isVisible,
                "floating": panel.isFloatingPanel,
                "level": panel.level,
                "frame": [
                    "x": panel.frameX,
                    "y": panel.frameY,
                    "width": panel.frameWidth,
                    "height": panel.frameHeight
                ],
                "screenMaxY": panel.screenMaxY,
                "distanceFromTop": panel.screenMaxY - panel.frameY - panel.frameHeight
            ],
            "console": [
                "expanded": coordinator.isExpanded,
                "agents": coordinator.agents.count,
                "commands": coordinator.commandResults.count,
                "commandQuery": coordinator.commandQuery,
                "sessions": coordinator.sessions.count,
                "activities": coordinator.recentActivities.count,
                "latestActivity": coordinator.recentActivities.first?.title ?? "",
                "project": coordinator.projectProfile.name,
                "preferences": [
                    "accent": coordinator.preferences.accent.rawValue,
                    "density": coordinator.preferences.density.rawValue,
                    "expandedWidth": coordinator.preferences.expandedWidth,
                    "expandedHeight": coordinator.preferences.expandedHeight,
                    "topOffset": coordinator.preferences.topOffset
                ]
            ],
            "codex": codexPayload(coordinator: coordinator),
            "cornerNote": [
                "expanded": coordinator.isCornerNoteExpanded,
                "noteLength": coordinator.cornerNoteText.count,
                "todos": coordinator.cornerTodos.count,
                "openTodos": coordinator.cornerTodos.filter { !$0.isDone }.count
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: healthPath), options: [.atomic])
        } catch {
            try? "Junimo health write failed: \(error)\n".write(toFile: errorPath, atomically: true, encoding: .utf8)
            fputs("Junimo health write failed: \(error)\n", stderr)
        }
    }

    /// 业务语义：健康快照暴露 normalized lifecycle counts，方便排查 UI 与状态源是否一致。
    private func codexPayload(coordinator: TaskCoordinator) -> [String: Any] {
        let codex = coordinator.codexFeatureSnapshot
        let monitor = codex.monitor
        let latestThread = monitor.latestThread
        let latestReview = codex.reviewItems.first
        return [
            "collapsedStatus": codex.collapsedStatusText,
            "usage": [
                "summary": monitor.usage.summaryText,
                "source": monitor.usage.source,
                "status": monitor.usage.status.rawValue,
                "detail": monitor.usage.detail
            ],
            "threads": [
                "count": monitor.threads.count,
                "active": monitor.activeThreadCount,
                "open": monitor.openThreadCount,
                "terminal": monitor.terminalThreadCount,
                "latestTitle": latestThread?.title ?? "",
                "latestStatus": latestThread?.status.rawValue ?? ""
            ],
            "reviews": [
                "count": codex.reviewItems.count,
                "latestCue": latestReview?.cueText ?? "",
                "latestTitle": latestReview?.title ?? "",
                "latestStatus": latestReview?.status.rawValue ?? ""
            ],
            "refreshedAt": ISO8601DateFormatter().string(from: monitor.refreshedAt)
        ]
    }
}
