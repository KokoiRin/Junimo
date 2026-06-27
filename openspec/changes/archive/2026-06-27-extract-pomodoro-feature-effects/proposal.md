# Change: 抽出 Pomodoro Feature Effect Owner

## Why

Pomodoro 是 Junimo 当前少数已经可用的真实功能。生命周期规则主要在 C++ core，但 Swift 侧仍由 `TaskCoordinator` 直接处理 start/cancel/advance、active timer projection，以及完成时创建系统通知请求。后续如果加入 focus/break 模式、完成动作、项目/session 关联，继续堆在 coordinator 会让兼容 facade 重新变成业务 owner。

## What Changes

- 新增 `PomodoroFeature`，拥有 Swift 侧 active Pomodoro projection 和 completion notification effect。
- `TaskCoordinator` 委托 Pomodoro start/cancel/advance 给 feature，并继续把 pending notification 交给 `NotificationOutbox`。
- 增加 direct smoke test，覆盖 feature 自身和 coordinator 兼容路径。
- 更新机会池和 Pomodoro feature spec，记录 Swift effect owner 边界。

## Out of Scope

- 不新增休息模式、循环模式或项目关联。
- 不改变 C++ core 的 Pomodoro lifecycle 规则。
- 不改变系统通知投递方式；投递仍属于 app shell `ReminderDeliveryBridge`。
