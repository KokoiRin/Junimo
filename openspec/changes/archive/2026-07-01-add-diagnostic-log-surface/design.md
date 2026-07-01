# Design: 主面板诊断日志

## 核心行为语义

当用户在 Junimo 里触发关键行为或系统收到重要状态变化时，系统应该记录一条带时间、等级、来源和说明的诊断日志；当用户打开主面板“日志”页时，应该能看到最近日志并手动写入一条调试探针来验证排查链路。

## 业务语义

- 日志条目包含：`id`、时间、等级、来源、标题、详情。
- 等级先限定为 `info`、`debug`、`warning`、`error`。
- 来源先限定为 app、Codex、Focus、Note、Capture、Debug。
- 日志是 bounded in-memory timeline，最近事件在前，避免日志无限增长。
- 日志页展示最近日志数量、最近一条事件和日志列表。
- “写入调试记录”按钮只写入一条 debug 级别探针，不触发外部权限或 shell 执行。
- 主面板字号整体提高，但不改变当前模块分页模型。

## 架构边界

新增 `DiagnosticLogFeature` 作为日志状态 owner。`TaskCoordinator` 只负责把现有 intent 和 feature effects 转发成日志事件，并暴露 `diagnosticLogs` 给 SwiftUI。

日志不放在 `JunimoSurfaceView` 内临时拼接，避免 UI 成为第二个事实源。C++ core 现有 `recentActivities` 仍表示产品活动时间线；诊断日志表示排查时间线，两者相关但不合并。

## 组件契约：DiagnosticLogFeature

- Responsibility：拥有应用内诊断日志条目、bounded 裁剪规则和调试探针写入。
- Not responsible for：不采集外部进程 stdout/stderr，不持久化，不上传，不解释 Codex 协议。
- Owner：`DiagnosticLogFeature` 是日志状态唯一 owner。
- Interface：调用方通过 `record(level:source:title:detail:date:)` 写入，通过 `entries` 读取最近日志。
- State：内部维护最近日志数组；派生的计数和最新日志由调用方从 `entries` 读取。
- Side effects：本轮无文件、网络或系统权限副作用。
- Invariants：最近日志在前；条目数量不超过上限；调试探针必须标记为 debug/debug source。
- Lifecycle：随 `TaskCoordinator` 初始化，随应用进程结束清空。
- Test surface：通过 `TaskCoordinator.diagnosticLogs` 和公开 intent 验证。

## 文件 / 模块布局

- 新增 `Sources/JunimoCore/DiagnosticLogFeature.swift`：日志模型 owner。
- 更新 `Sources/JunimoCore/JunimoModels.swift`：公共日志值对象。
- 更新 `Sources/JunimoCore/TaskCoordinator.swift`：记录关键行为日志并暴露投影。
- 更新 `Sources/Junimo/JunimoSurfaceView.swift`：新增日志页、调试按钮和字号调整。
- 更新 direct smoke tests 和 app smoke tests：覆盖日志语义和页面 copy。
- 更新 README / docs / OpenSpec specs：同步最终能力。

## 验证策略

- Swift direct tests 覆盖：启动后有日志、用户 intent 写日志、日志裁剪、调试探针。
- App smoke tests 覆盖：主面板包含 `logs` 页面、中文 copy 包含“日志”、主面板基础字号变大。
- OpenSpec strict validate 覆盖规格格式。
- 手动/截图仍用于最终视觉确认，本轮不引入像素级自动验证。
