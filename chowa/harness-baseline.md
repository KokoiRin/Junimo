# Chowa Harness Baseline

## 当前结论

Junimo 已经具备后续 Chowa 迭代需要的最小闭环：长期 OpenSpec specs 描述已完成能力，direct Swift smoke 和 C++ smoke 保护核心行为，app health / functional scenario 保护可运行性，`scripts/verify.sh` 把这些验证串成一次完整本地 harness。

当前没有 active OpenSpec change。已完成 changes 已归档到 `openspec/changes/archive/`，长期要求已同步到 `openspec/specs/`。下一轮 Chowa 应从 `chowa/opportunities.md` 选择新的 P0。

## 文档-测试-代码地图

| 语义 | OpenSpec | 测试 / harness | 代码入口 |
| --- | --- | --- | --- |
| Codex app-server 和 exec JSONL 事件进入同一个 monitor 状态面 | `openspec/specs/codex-realtime-adapter/spec.md` | `scripts/test.sh` 中的 realtime parser / coordinator smoke，`scripts/verify.sh` 全量验证 | `Sources/JunimoCore/CodexStatusProvider.swift`，`Sources/JunimoCore/TaskCoordinator.swift` |
| Realtime stream 降级不阻塞 snapshot fallback | `openspec/specs/codex-realtime-adapter/spec.md` | `Tests/JunimoAppDirectTests/main.swift` 使用 fake provider / fake stream | `Sources/Junimo/CodexMonitorRefreshBridge.swift` |
| Codex active thread 进入 completed / failed 时产生通知和活动记录 | `openspec/specs/codex-realtime-adapter/spec.md` | `Tests/JunimoDirectTests/main.swift`，`Tests/JunimoTests/TaskCoordinatorTests.swift` | `TaskCoordinator.updateCodexThread(...)` |
| Codex review attention 独立于系统通知队列，直到用户确认才清除 | `openspec/specs/codex-status-attention/spec.md`，`openspec/specs/codex-review-attention/spec.md` | `scripts/test.sh` 覆盖通知 delivered 后 review item 仍保留、ack 后清除、active retry 清 stale item | `CodexReviewItem`，`TaskCoordinator.codexReviewItems`，`acknowledgeCodexReview(...)` |
| 岛内 UI 在 collapsed / expanded 状态提示待 review 结果，并用动画强调完成/失败 | `openspec/specs/codex-status-attention/spec.md` | `scripts/verify_functional_scenario.sh` 保护 app 可运行主链路；当前没有像素级断言 | `Sources/Junimo/JunimoSurfaceView.swift` |
| C++23 core 继续拥有 portable action / Pomodoro / command / preference 状态 | `openspec/specs/cpp23-core-framework/spec.md`，`openspec/specs/swift-cpp-core-bridge/spec.md` | `scripts/test_cpp.sh`，`scripts/test.sh`，`scripts/verify.sh` | `Core/`，`Sources/JunimoCore/CppCoreBridge.swift`，`CoreBackends.swift` |

## 推荐迭代方式

1. 轻量红绿循环优先运行 `scripts/test.sh`；触碰 C++ core 时加跑 `scripts/test_cpp.sh`。
2. 触碰 app shell、panel、health、functional scenario 或 OpenSpec 状态时，收口前运行 `scripts/verify.sh`。
3. 每个 Chowa 目标都要在 design / tasks 中写清楚可观察语义，并在测试名或中文注释中说明对应不变量。
4. 若实现已经存在，按 Chowa 半成品入口处理：先补目标和当前不做范围，再做 09 完成检查，不从头生成重复 proposal。

## 当前测试缺口

- UI attention cue 有实现和 spec，但没有精确的视觉断言；目前由 functional app scenario 和代码检查间接覆盖。
- 菜单栏 Show / Quit 已实现并有 spec / health 间接验证，但没有自动点击测试。
