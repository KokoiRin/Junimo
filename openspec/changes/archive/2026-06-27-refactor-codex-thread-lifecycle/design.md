# Design: Refactor Codex Thread Lifecycle

## Core Behavior

当 Codex 仍存在非终态对话时，Junimo 的刘海状态必须表达“Codex 还有待关注工作”，不能因为一个线程完成或一个 snapshot 缺少 active 状态就回到纯用量；只有没有 review、没有 active/waiting、没有 open/unknown 线程时，才显示 quota summary。

## Current Failure Modes

1. `notLoaded` 被归一化为 `.idle`。
   - app-server `thread/list` 的 `notLoaded` 只说明当前短连接没有加载线程运行态，不等于完成、失败或可忽略。
2. 解析阶段先 `prefix(8)`。
   - 这会在 lifecycle 判断前丢掉旧的 active/open 线程，后续 coordinator 会把丢失误读成完成。
3. snapshot 缺失会触发 completed。
   - `missingActiveThreads` 把“没有出现在本次 snapshot”当成 terminal transition；这混淆了数据源完整性和业务生命周期。
4. UI collapsed 状态只有 review / active / quota 三层。
   - 缺少 open/unknown 层，所以“仍有未完成对话但暂无 active 信号”会掉回 quota。

## Lifecycle Model

新增或等价整理一个生命周期归一化模块，建议命名为 `CodexThreadLifecycleReducer`，位于 `JunimoCore`。

### States

- `running`：Codex 正在执行，没有等待 flags。
- `waiting`：Codex active 且等待用户、审批或其他输入。
- `open`：对话存在且非归档，但当前 source 没有明确运行态；例如 app-server `notLoaded` 或普通 `idle` 的非归档线程。
- `completed`：明确收到 completed/succeeded/done/closed terminal 事件或 cloud terminal status。
- `failed`：明确收到 failed/error/cancel/systemError terminal 事件或 cloud failure status。

### Display Priority

Collapsed status 按以下优先级生成：

1. pending review：`Codex done` / `Codex failed`
2. waiting thread：`Codex waiting`
3. running thread：`Codex running`
4. open thread：`Codex open N`
5. quota summary：例如 `80% left`

`open` 不应显示成 `running`，避免制造虚假的执行中状态；但它也不应被 quota 覆盖。

## Component Contract: CodexThreadLifecycleReducer

- Responsibility：把 raw Codex source observations 和 realtime lifecycle events 归一化为 Junimo 可展示、可测试的 thread lifecycle。
- Not responsible for：不启动 Codex 进程，不写 UI，不发送系统通知，不决定窗口布局。
- Owner：`JunimoCore` 拥有 lifecycle 规则；`TaskCoordinator` 拥有 published state 和通知 / review 副作用。
- Interface：
  - 输入：snapshot observations、realtime thread events、exec lifecycle events、当前已知 threads。
  - 输出：归一化后的 thread list、active count、open count、terminal transition effects。
  - 错误语义：source 缺失或 snapshot 不完整只能降级为 unknown/open/stale，不能伪造 completed。
- State：线程生命周期以 reducer 输出为唯一权威；UI 文案和 health counts 都从同一份 normalized state 派生。
- Side effects：reducer 不产生副作用；`TaskCoordinator` 根据 explicit terminal transition 创建 notification 和 review item。
- Invariants：
  - `notLoaded` 永远不能被归类为 terminal。
  - snapshot absence 永远不能单独创建 completion review。
  - active/waiting/open 线程在排序截断前必须被保留和参与优先级计算。
  - 同一线程不能同时拥有 open/active 和 terminal 状态。
  - review 只来自明确 terminal transition，不来自 UI acknowledge 或 snapshot 缺失。
- Lifecycle：reducer 随每次 snapshot 或 realtime event 同步执行；旧线程在没有明确 terminal 事件时最多降级为 open/stale，不自动完成。
- Test surface：通过 `TaskCoordinator.refreshCodexMonitor(...)`、`applyCodexRealtimeEvent(...)`、`codexCollapsedStatusText`、health snapshot counts 验证，不测试 private 方法。

## Adapter Boundaries

- `CodexStatusProvider` / parsers 只负责保留 raw source status 并做最小字段解析。
- `TaskCoordinator` 不再内联复杂 lifecycle 判定；它调用 reducer 后应用输出，并负责通知、review、activity 等副作用。
- `LaunchHealthReporter` 输出至少包含：
  - `threads.active`
  - `threads.open`
  - `threads.terminal`
  - `reviews.count`
  - `collapsedStatus`

## Sorting And Truncation

输入源可以请求较大的 limit，例如 50。归一化时先合并所有 source observations，再按展示优先级输出 UI list：

1. pending review / terminal recent
2. waiting
3. running
4. open
5. recent idle/terminal history

最终 UI list 可继续限制为 8 条，但 active/open 计数必须来自完整归一化结果，而不是截断后的 8 条。

## Test Strategy

- L1 parser/reducer 测试：覆盖 app-server `active`、`activeFlags`、`notLoaded`、`idle`、`systemError`，以及 cloud terminal statuses。
- L1 coordinator 测试：覆盖多个线程中一个 completed 后仍有 open thread，collapsed 显示 `Codex open N` 而非 quota。
- L1 regression 测试：snapshot 缺失旧 active 不创建 completion review。
- L2 bridge/fake provider 测试：snapshot refresh 发布 UI 更新，health 输出 active/open/review counts。
- 手动验证：真实 Codex app 中有多个非归档对话时，Junimo collapsed 状态与 health snapshot 一致。

## Migration Plan

1. 先加 RED 测试锁定误判：`notLoaded`、截断前保留、snapshot absence 不完成、open display priority。
2. 引入 lifecycle reducer 或等价小模块。
3. 调整 `CodexStatusProvider` 解析与 snapshot limit，避免解析前丢弃重要线程。
4. 调整 `TaskCoordinator` 只对明确 terminal transition 产生 review。
5. 更新 health、docs、OpenSpec specs。

## Risks

- `open` 数量可能包含用户只是没归档的旧对话。这个风险通过文案表达为 `open` 而非 `running` 来缓解。
- Codex app-server 协议可能继续变化。保留 raw status 和 integration finding 能帮助诊断未知状态。
- 如果后续接入真实岛内 launch flow，exec stream 会给更强的 lifecycle source；本设计不阻塞该方向。
