# Change: 抽出 Console Feature

## Why

`TaskCoordinator` 已经逐步退回兼容 facade，但它仍直接拥有 actions、command palette、project profile、recent activities、sessions，以及 `performAction` 里的 Codex 占位启动逻辑。机会池里下一步 P0 是从岛内启动真实 `codex exec --json`，如果继续让 coordinator 同时管理 command 搜索、action 执行和 agent 启动 effect，真实 Codex launch 很容易继续塞进这个兼容层。

## What Changes

- 新增 `ConsoleFeature`，拥有 console action/catalog/session/activity 的 Swift 投影。
- `ConsoleFeature.performAction` 通过现有 core 执行动作并返回 agent start effect，供 `TaskCoordinator` 兼容地映射到当前 Codex placeholder thread。
- `TaskCoordinator` 委托 command query、action execution、activity/session refresh 给 `ConsoleFeature`。
- 增加 direct smoke test，验证 feature 自身和 coordinator 兼容路径仍保持现有行为。
- 更新机会池和 OpenSpec spec，记录真实 Codex exec 前的 action/command 边界。

## Out of Scope

- 不实现真实 `codex exec --json`。
- 不新增通用 adapter registry。
- 不改变 SwiftUI 面板布局或 command palette 文案。
- 不迁移 UI preferences；preferences 可作为独立较小切片处理。
