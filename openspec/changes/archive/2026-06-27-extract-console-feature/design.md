# Design: Console Feature

## Target

[P0][架构预备] 当面板需要搜索 command、执行 action、展示 project profile、activities 和 sessions 时，系统应该通过 `ConsoleFeature` 维护 Swift 投影和 action effects，而不是让 `TaskCoordinator` 继续直接拥有这些规则。

## Current Evidence

`TaskCoordinator` 当前直接拥有：

- `agents`
- `actions`
- `recentActivities`
- `commandQuery`
- `commandResults`
- `projectProfile`
- `sessions`
- `performAction`
- `updateCommandQuery`
- `refreshConsoleState`
- `recordActivity`

其中 `performAction(id: "codex")` 还硬编码了 `junimo-local-codex` placeholder thread。下一步做真实 Codex exec 时，必须有一个清晰位置表达“action 触发了 agent start effect”，否则会继续污染 coordinator。

## Component Contract: `ConsoleFeature`

- Responsibility：维护 console action/catalog/session/activity 的 Swift 投影；执行 action；返回 agent start effects；支持命令搜索。
- Not responsible for：不启动真实外部 agent；不解析 Codex 协议；不拥有 Pomodoro/Codex/Corner Note 业务状态；不管理 UI preferences。
- Owner：feature-store 层拥有 console shell 投影；C++ core 仍拥有 portable action/session/activity policy。
- Interface：
  - `agents/actions/recentActivities/commandQuery/commandResults/projectProfile/sessions`
  - `updateCommandQuery(_:)`
  - `performAction(id:now:) -> ConsoleFeatureEffects`
  - `recordActivity(title:detail:date:)`
  - `updateAgentProjection(id:status:detail:)`
  - `refreshState()`
- State：feature 的 Swift state 是 core snapshots 和局部 agent projection 的 UI-ready 投影。
- Side effects：feature 调用 `ActionCore.run` 和 `ConsoleStateCore.recordActivity`；真实 Codex execution 不在本轮。
- Invariants：
  - command query 更新只影响 query 和 command results。
  - unknown action 不产生 effects，也不刷新成虚假状态。
  - agent action running result 会返回 agent start effect，供上层映射到现有 Codex placeholder 或未来真实 adapter。
  - `TaskCoordinator` 不直接调用 `ActionCore.run`、`CommandCatalogCore.searchCommands` 或 `SessionTimelineCore.recentSessions`。
- Lifecycle：`TaskCoordinator` 初始化 `ConsoleFeature`；公开属性继续作为兼容投影同步给 SwiftUI。
- Test surface：direct smoke 通过 `ConsoleFeature` 公开接口和 coordinator 公开状态验证。

## Validation Strategy

- Direct smoke:
  - `ConsoleFeature` 初始化后暴露 project profile、default command results。
  - `updateCommandQuery("focus")` 返回 Pomodoro command。
  - `performAction("codex")` 刷新 running agent/session/activity，并返回 agent start effect。
  - `TaskCoordinator.performAction("codex")` 仍创建当前 placeholder Codex thread。
- Existing smoke:
  - `scripts/test.sh` 保持 action、command、Codex placeholder 和 Pomodoro 兼容行为。
  - `scripts/build.sh` 确认 app target 仍编译。
  - `openspec validate --all --strict` 保持 specs 一致。

## Design Review

- 业务语义：通过。只移动 console action/command 投影和 action effects，不改变可见 UI 行为。
- 架构边界：通过。feature 位于 coordinator facade 与 core/adapters 之间，符合现有 feature-store 提取方向。
- 组件契约：通过。真实 Codex exec 和 adapter registry 明确不在本轮。
- 任务可验证性：通过。新增 feature 和 coordinator 兼容路径都有 direct smoke。
- `chowa/skill-gaps.md`：无新增。
