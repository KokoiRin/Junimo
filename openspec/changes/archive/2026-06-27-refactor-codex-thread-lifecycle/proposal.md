# Refactor Codex Thread Lifecycle

## Why

Junimo 的 Codex 刘海状态现在把 `thread/list` 的即时 `status.type` 当成唯一权威源。实际诊断里，Codex app-server 会返回大量非归档线程为 `notLoaded`，这些线程既不是完成态，也不能等同于 idle；当前实现却把未知状态归为 idle，并且在解析前只保留最新 8 条线程。

这导致三个用户可见问题：

- 一个线程完成后，刘海可能直接回到剩余用量，即使还有其他未完成 / 未归档对话。
- 较旧但仍需要关注的线程可能被 `prefix(8)` 截断，从而被后续 snapshot 误判为完成。
- `missingActiveThreads` 把“本轮 snapshot 没出现”直接视为 completed，这会把数据源不完整误当成生命周期事件。

## What Changes

- 引入明确的 Codex thread lifecycle 归一化层，把 raw app-server / cloud / exec 状态转换成稳定生命周期状态。
- 区分 running、waiting、open/unknown、completed、failed，而不是把未知状态压成 idle。
- 只在明确 terminal 事件或明确 terminal source status 出现时创建 completion review；snapshot 缺失不得创建完成提示。
- 先完成 lifecycle 归一化与排序，再截断 UI 展示数量，保证 active/open 线程不会被最新 8 条截断误丢。
- 更新健康快照和 UI 摘要，让用户能看到 active、open、review 三类状态。

## Non-Goals

- 本轮不实现岛内 prompt/workspace 启动真实 Codex run。
- 本轮不抽象通用 agent registry。
- 本轮不反向模拟 Codex app 内部所有 UI 状态，只消费当前 app-server、cloud、exec 可观察事件。
