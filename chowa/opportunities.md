# Opportunities

## Open

- [P1][架构重构] 当第二个真实 agent adapter 出现后，再抽象通用 adapter registry；当前先把 Codex adapter 边界拆清楚，不提前做通用注册表。
- [P1][调试/验证] 为 collapsed attention badge 和菜单栏 Show/Quit 增加 UI 级验证；当前由 functional scenario、health snapshot 和代码检查间接覆盖。

## Done

- [P0][新增需求] 已安装的 Junimo 可以从菜单检查 GitHub Release 新版本，发现新版本后通过 `Install Update...` 按钮从当前安装位置更新应用。归档：openspec/changes/archive/2026-06-28-add-self-update-check/
- [P0][新增需求] Codex 状态提醒体验：Junimo 不伪造本地 running thread，只呈现 adapter 观测到的 running/waiting/done/failed，并在完成/失败时给出明显、持久、可清除的提示动画。归档：openspec/changes/archive/2026-06-27-improve-codex-status-attention/
- [P0][架构预备] 抽出 Preferences feature owner：`PreferencesFeature` 拥有 UI preferences/theme 投影和 accent/density intents，`TaskCoordinator` 只保留 layout callback 兼容路径。归档：openspec/changes/archive/2026-06-27-extract-preferences-feature/
- [P0][架构预备] 抽出 Console feature owner：`ConsoleFeature` 拥有 actions、command search、project profile、activities、sessions 和 running agent start effects，`TaskCoordinator` 只做兼容委托。归档：openspec/changes/archive/2026-06-27-extract-console-feature/
- [P0][架构重构] 抽出 Junimo runtime composition：`JunimoRuntime` 组合 coordinator、提醒投递、Codex monitor 和 launch health，`AppDelegate` 回到 AppKit surface 生命周期入口。归档：openspec/changes/archive/2026-06-27-extract-junimo-runtime-composition/
- [P0][架构预备] 抽出 Pomodoro feature effect owner：`PomodoroFeature` 维护 Swift active timer 投影和 completion notification effect，`TaskCoordinator` 只做兼容委托。归档：openspec/changes/archive/2026-06-27-extract-pomodoro-feature-effects/
- [P0][架构重构] 拆分 Codex adapter/provider 边界：contracts、process runner、app-server client、realtime streams、snapshot parser、realtime parser、monitor service 分文件，app bridge 通过 typed sink 连接 `CodexFeature`。归档：openspec/changes/archive/2026-06-27-split-codex-status-provider/
- [P1][架构预备] 抽出 Corner Note feature owner：`CornerNoteFeature` 拥有 expanded/text/todos Swift 投影，`TaskCoordinator` 只做兼容委托，内容变更仍通过 `CornerNoteCore`。归档：openspec/changes/archive/2026-06-27-extract-corner-note-feature/
- [P1][架构预备] 抽出 NotificationOutbox 基础模块：Codex/Pomodoro 等 feature 产生的系统通知请求统一进入 outbox，`TaskCoordinator.pendingNotifications` 只做 app shell 兼容投影。归档：openspec/changes/archive/2026-06-27-extract-notification-outbox/
- [P0][架构预备] 定义 Junimo 模块结构并抽出第一段 Codex feature-store skeleton：`CodexFeature` 拥有 monitor/review/collapsed/agent projection，coordinator 只做兼容委托，health 读取 feature snapshot。归档：openspec/changes/archive/2026-06-27-define-junimo-module-architecture/
- [P0][架构重构] 重构 Codex thread lifecycle 状态模型：区分 running / waiting / open / terminal，避免一个完成事件或不完整 snapshot 让刘海误回 quota。归档：openspec/changes/archive/2026-06-27-refactor-codex-thread-lifecycle/
- [P0][新增需求] Codex 任务完成或失败后，collapsed 刘海右侧优先显示 `Codex done` / `Codex failed` 结果提示。
- [P0][调试/验证] 建立 Chowa 可用的本地 harness 基线：`scripts/verify.sh` 串联 Swift direct smoke、C++ smoke、app build、launch health、functional scenario、OpenSpec spec validate 和 `git diff --check`。
- [P0][调试/验证] 已归档全部完成的 OpenSpec changes，并同步长期 specs 到 `openspec/specs/`。
- [P1][调试/验证] 已为 `CodexMonitorRefreshBridge` 增加 fake provider / fake stream 测试接缝，验证 realtime 降级不阻塞 snapshot fallback。
