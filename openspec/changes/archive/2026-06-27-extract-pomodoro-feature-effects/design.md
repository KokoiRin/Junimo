# Design: Pomodoro Feature Effect Owner

## Target

[P0][架构预备] 当 Pomodoro 生命周期产生 Swift 侧 UI projection 或 completion notification effect 时，系统应该通过 `PomodoroFeature` 表达，而不是让 `TaskCoordinator` 直接拥有 Pomodoro effect 规则。

## Component Contract: `PomodoroFeature`

- Responsibility：调用 `PomodoroCore` 执行 start/cancel/advance，维护 active timer projection，并在 completion 时产出 `NotificationRequest` effect。
- Not responsible for：不投递系统通知；不拥有 notification queue；不记录 session timeline；不改变 C++ core lifecycle policy。
- Owner：Swift feature-store 层拥有 Pomodoro UI-ready projection 和 completion effect mapping；C++ core 仍拥有 portable timer lifecycle。
- Interface：
  - `activePomodoro`：公开当前 active timer projection。
  - `start(duration:now:)`：启动 timer 并刷新 active projection。
  - `cancel(now:)`：取消 timer 并刷新 active projection。
  - `advanceTime(to:) -> PomodoroFeatureEffects`：推进时间，完成时返回通知 effect。
- State：`activePomodoro` 是从 `ConsoleStateCore.activePomodoro()` 刷新的投影，不是第二个 timer 权威源。
- Side effects：feature 只返回 notification effect；系统投递仍由 app shell bridge 完成。
- Invariants：
  - 未完成的 advance 不产生 notification effect。
  - 完成的 advance 清空 active projection 并只返回 completion notification request。
  - `TaskCoordinator.pendingNotifications` 仍只来自 `NotificationOutbox`。
- Lifecycle：`TaskCoordinator` 初始化 feature；公开 Pomodoro 方法只做兼容委托。
- Test surface：direct test 通过 `PomodoroFeature` 公开接口和 coordinator 公开状态验证，不测试 private 方法。

## Validation Strategy

- Direct smoke:
  - `PomodoroFeature.start` 暴露 active timer。
  - 未到期 `advanceTime` 不产生 notification。
  - 到期 `advanceTime` 清空 active timer 并产生 “Pomodoro complete” notification。
  - coordinator 的 `startPomodoro` / `advanceTime` 仍能更新 `activePomodoro` 和 `pendingNotifications`。
- Existing tests:
  - `scripts/test.sh` 保持 action/command/pomodoro 兼容行为。
  - `openspec validate --all --strict` 保持 specs 一致。

## Design Review

- 业务语义：通过。只移动 Swift effect owner，不改 timer 行为。
- 架构边界：通过。C++ core 仍是 lifecycle policy owner；Swift feature 只拥有 projection/effect mapping。
- 组件契约：通过。通知投递和队列不进入 feature。
- 任务可验证性：通过。feature 和 coordinator 都有 direct smoke 覆盖。
- `chowa/skill-gaps.md`：无新增。
