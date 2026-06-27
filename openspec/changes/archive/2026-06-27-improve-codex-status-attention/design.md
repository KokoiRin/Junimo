# Design: Codex 状态提醒体验

## Target

[P0][新增需求] 当外部 Codex/agent workflow 产生 running、waiting、completed 或 failed 状态时，Junimo 应该可信地呈现状态；完成/失败时 collapsed island 给出明显、持久、可清除的提示动画。

## Core Behavior Semantics

当没有 adapter snapshot 或 realtime event 证明 Codex 正在运行时，Junimo 不应该伪造 running thread。  
当 Codex thread 从 running / waiting / open 等未终结状态进入 completed / failed 时，Junimo 应该创建 review attention、优先显示 `Codex done` / `Codex failed`，并为 UI 提供明确的提示语气。  
当用户确认提示后，review attention 清除，collapsed 状态回到剩余真实工作或 quota。

## Component Contract: `CodexFeature`

- Responsibility：拥有 Codex quota、thread lifecycle、review attention、collapsed status 和 attention cue 投影。
- Not responsible for：不启动 Codex 进程；不拥有 AppKit/SwiftUI 动画；不投递系统通知。
- Owner：`JunimoCore`。
- Interface：
  - `refreshMonitor(_:)`
  - `applyRealtimeEvent(_:)`
  - `updateThread(...)`
  - `acknowledgeReview(...)`
  - `CodexReviewItem.attentionCue`
- State：`monitor`、`reviewItems`；review item 是待用户确认的状态权威源。
- Side effects：只返回 notification/activity effects，由 coordinator/runtime 消费。
- Invariants：
  - Snapshot absence 不能把 active thread 伪造成 completed。
  - 只有明确 terminal transition 才创建 review attention。
  - 新的 non-terminal update 会清除同 thread 的旧 review attention。
  - `collapsedStatusText` 优先级为 review cue > active status > open count > quota。
- Test surface：direct smoke 通过 public feature/coordinator API 验证状态和 cue。

## Component Contract: `JunimoSurfaceView` Attention Presentation

- Responsibility：把 `CodexReviewItem.attentionCue` 变成 collapsed island 上的视觉提醒和确认入口。
- Not responsible for：不解释 Codex lifecycle；不决定 terminal transition。
- Owner：app SwiftUI surface。
- Interface：读取 `coordinator.codexReviewItems`、`coordinator.codexCollapsedStatusText`；点击调用 `acknowledgeLatestCodexReview()`。
- State：仅拥有局部 animation phase，不拥有业务状态。
- Side effects：用户点击确认；SwiftUI 动画。
- Invariants：
  - 有 review attention 时，右侧 pill 与 badge 均可确认。
  - completed 和 failed 使用不同图标/语气。
  - 动画不能改变业务状态，也不能依赖 3 秒自动消失。
- Test surface：build 验证 SwiftUI 编译；direct smoke 验证 cue 投影；manual/functional scenario 验证 app 可启动。

## Data Flow

1. Codex adapter snapshot 或 realtime event 进入 `TaskCoordinator` typed entrypoint。
2. `TaskCoordinator` 委托 `CodexFeature` 更新 lifecycle。
3. terminal transition 产生 notification/activity effects 和 `CodexReviewItem`。
4. SwiftUI 读取 `codexReviewItems.first?.attentionCue` 渲染完成/失败提示动画。
5. 用户点击 pill/badge 后调用 acknowledge，review attention 被清除。

## Validation Strategy

- Core direct smoke：
  - Codex action 不再伪造 local running thread。
  - running/waiting/open/completed/failed 的 collapsed priority 正确。
  - completed / failed review item 暴露对应 attention cue。
  - notification delivered 不清 review，ack 才清 review。
- App/build：
  - `scripts/test.sh`
  - `scripts/build.sh`
  - `scripts/verify_functional_scenario.sh`
  - `openspec validate --all --strict`
  - `git diff --check`

## Design Review

- 业务语义：通过。Junimo 是状态提醒中心，不是 Codex 启动器。
- 架构边界：通过。状态规则在 `CodexFeature`，动画在 SwiftUI 局部状态。
- 组件契约：通过。Core cue 投影可测试，UI 动画不反向拥有业务状态。
- 任务可验证性：通过。状态正确性有 direct smoke；动画通过 build 和功能脚本验证。
- `chowa/skill-gaps.md`：无新增。
