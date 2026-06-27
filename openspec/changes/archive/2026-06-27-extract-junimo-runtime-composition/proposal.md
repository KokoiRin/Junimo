# Change: 抽出 Junimo Runtime Composition

## Why

Junimo 的 app 启动入口已经不只是 AppKit 生命周期。`AppDelegate` 现在同时创建 `TaskCoordinator`、提醒投递、Codex 监控、健康快照、功能健康场景、状态栏菜单和两个 panel controller。这个结构在早期很方便，但后续继续增加 Codex exec、Pomodoro session、Project profiles 或更多 adapter 时，新的功能 wiring 会继续堆到 `AppDelegate`，也会让测试只能绕过真实启动组合。

## What

- 新增 app 层 `JunimoRuntime`，作为 feature stores、platform bridges、monitor service 和 diagnostics 的运行时组合点。
- 让 `AppDelegate` 只保留 AppKit 生命周期、窗口/controller 创建、状态栏菜单和 panel diagnostics 读取。
- 为 runtime composition 增加 fake-backed direct smoke test，验证 start/stop、Codex monitor wiring、提醒投递 wiring 和健康场景入口。
- 更新架构文档和机会池，记录 runtime composition 已成为后续功能挂载位置。

## Out of Scope

- 不改变 SwiftUI 面板布局。
- 不改变 Codex thread lifecycle、quota、review attention 或 Pomodoro 业务规则。
- 不抽象通用 adapter registry；等第二个真实 agent adapter 出现后再判断。
- 不把 AppKit panel controller 移入 runtime；panel 仍属于 app shell。
