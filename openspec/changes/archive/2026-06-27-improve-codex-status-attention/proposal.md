# Change: Codex 状态提醒体验

## Why

Junimo 当前更适合作为外部 Codex/agent workflow 的状态中心，而不是新的 Codex 启动入口。用户已经明确不需要从 Junimo 直接调用 Codex；真正痛点是状态要可信、完成/失败要明显可见、并且提示可以被明确清除。

现有结构已经有 `CodexFeature`、`CodexMonitorRefreshBridge`、review attention 和 collapsed status pill，但仍有两个体验风险：

- Codex dock action 仍会制造一个本地 placeholder running thread，容易让“正在运行”状态不可信。
- 完成/失败提示虽然有 badge/pill，但视觉动势偏弱，不足以承担任务完成后的注意力提醒。

## What Changes

- 停止把 Codex action 映射为本地 placeholder running thread；Codex running/waiting/done/failed 只来自 adapter snapshot 或 realtime event。
- 增加可测试的 Codex attention cue 表达，区分 completed / failed 的文案、图标和视觉语气。
- 强化 collapsed island 完成/失败提示：状态 pill、halo、badge 使用更明显的呼吸/扫光/弹性动效；用户点击后仍可确认清除。
- 更新机会池和文档，明确 Junimo 当前不做 Codex 启动器。

## Out of Scope

- 不从岛内启动 `codex exec`。
- 不做多轮 chat UI、diff review UI 或审批 UI。
- 不做通用 agent adapter registry。
- 不增加像素级 UI 自动化；本轮通过 core direct smoke、app build 和功能脚本验证。
