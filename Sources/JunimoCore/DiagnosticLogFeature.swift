import Foundation

/// 诊断日志 feature 拥有 Junimo 应用内排查时间线；它不采集外部进程输出，也不负责持久化或上传。
public struct DiagnosticLogFeature {
    public private(set) var entries: [DiagnosticLogEntry]
    private let limit: Int

    /// 业务语义：日志时间线初始化时记录 app 启动事件，帮助用户判断当前面板状态属于哪次进程生命周期。
    public init(now: Date, limit: Int = 80) {
        self.limit = max(1, limit)
        self.entries = []
        record(
            level: .info,
            source: .app,
            title: "Junimo 已启动",
            detail: "本地控制台已初始化",
            date: now
        )
    }

    /// 业务语义：所有日志写入都经过同一个入口，保证最近在前和 bounded timeline 不变量。
    public mutating func record(
        level: DiagnosticLogLevel,
        source: DiagnosticLogSource,
        title: String,
        detail: String,
        date: Date
    ) {
        entries.insert(
            DiagnosticLogEntry(
                level: level,
                source: source,
                title: title,
                detail: detail,
                date: date
            ),
            at: 0
        )
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
    }

    /// 业务语义：调试探针只验证日志链路和 UI 刷新，不触发 shell、截图、通知或网络副作用。
    public mutating func recordDebugProbe(now: Date) {
        record(
            level: .debug,
            source: .debug,
            title: "调试探针",
            detail: "手动写入一条诊断日志，用于确认日志链路正常",
            date: now
        )
    }
}
