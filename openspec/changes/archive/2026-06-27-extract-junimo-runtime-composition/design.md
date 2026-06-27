# Design: Junimo Runtime Composition

## Target

[P0][架构重构] 当应用启动需要组合 feature state、platform bridge、Codex monitor 和 diagnostics 时，系统应该通过一个 runtime composition 对象管理依赖与生命周期，而不是让 `AppDelegate` 继续成为产品 wiring 的聚合点。

## Current Evidence

`AppDelegate` 直接拥有：

- `TaskCoordinator`
- `ReminderDeliveryBridge`
- `CodexMonitorRefreshBridge`
- `LaunchHealthReporter`
- launch health scenario mutations
- panel controller 创建与状态栏菜单

这混合了两类职责：AppKit surface 生命周期，以及产品 runtime 依赖组合。后续每新增一个 feature bridge 或 adapter，都会继续修改 AppDelegate，测试也难以覆盖真实组合路径。

## Component Contract: `JunimoRuntime`

- Responsibility：组合 app 层运行时依赖，拥有 `TaskCoordinator`、提醒投递 bridge、Codex monitor bridge、launch health reporter，并提供 start/stop 和健康场景入口。
- Not responsible for：不创建 AppKit panel、SwiftUI view、status item；不决定 Codex/Pomodoro/Corner Note 的业务规则；不投递真实 UI 事件。
- Owner：app 层 runtime composition，是平台 bridge 生命周期的 owner；业务状态仍由 `TaskCoordinator` 兼容 facade 和各 feature store 拥有。
- Interface：
  - `coordinator`：AppDelegate / controllers 读取并传给 SwiftUI。
  - `start(onCodexMonitorUpdated:)`：启动提醒投递和 Codex monitor。
  - `stop()`：停止 Codex monitor，释放运行中 bridge。
  - `runLaunchHealthScenario()`：触发现有 functional health scenario。
  - `writeHealth(panel:)`：通过公开 coordinator snapshot 和 panel diagnostics 写健康快照。
- State：
  - `TaskCoordinator` 是 product state 兼容入口。
  - runtime 只保存 bridge/service 引用以维持生命周期。
- Side effects：
  - 系统通知由 `ReminderDeliveryBridge` 和注入的 `ReminderDelivering` adapter 负责。
  - Codex probe/realtime 由 `CodexMonitorRefreshBridge` 和注入 provider/stream 负责。
  - 健康文件写入由 `LaunchHealthReporter` 负责。
- Invariants：
  - `AppDelegate` 不直接创建 feature/platform bridge。
  - runtime start 后应立刻走一次 Codex snapshot refresh，并启动 realtime stream。
  - runtime stop 后应停止 Codex realtime stream。
  - 提醒投递仍通过 `TaskCoordinator.pendingNotifications` 兼容投影，不新增第二个通知队列。
- Lifecycle：
  - App 启动时创建 runtime。
  - panel 创建后调用 `start` 和 `writeHealth`。
  - App 终止时调用 `stop`。
- Test surface：使用 fake snapshot provider、fake realtime stream、fake reminder adapter，通过公开 coordinator 状态、fake call counts 和 callback 次数验证。

## Behavior

启动流程变为：

1. `AppDelegate` 创建 `JunimoRuntime`。
2. `AppDelegate` 用 `runtime.coordinator` 创建 panel controllers。
3. `AppDelegate` 调用 `runtime.start(...)`。
4. Codex monitor 更新时，AppDelegate 提供 panel diagnostics 并让 runtime 写 health snapshot。
5. termination 调用 `runtime.stop()`。

## Validation Strategy

- App direct smoke test：
  - fake provider 首次 snapshot 能进入 runtime coordinator。
  - fake realtime stream 会被 start/stop。
  - fake stream degraded finding 进入 coordinator。
  - Pomodoro completion 产生 notification 后，runtime reminder bridge 用 fake adapter 投递并清空 pending queue。
  - `runLaunchHealthScenario()` 会触发 corner note、compact density 和 Pomodoro 状态。
- Build：
  - `scripts/build.sh` 确认 app target 仍能编译。
  - `scripts/test.sh` 覆盖 direct smoke。
  - `openspec validate --all --strict` 确认规格一致。

## Design Review

- 业务语义：通过。目标是运行时组合边界，不改变用户可见 UI 行为。
- 架构边界：通过。runtime 位于 app shell 和 feature/adapters 之间，符合 docs 中目标结构。
- 组件契约：通过。状态、bridge 生命周期和副作用边界清楚。
- 任务可验证性：通过。新增 runtime 有 fake-backed direct test。
- `chowa/skill-gaps.md`：无新增。
