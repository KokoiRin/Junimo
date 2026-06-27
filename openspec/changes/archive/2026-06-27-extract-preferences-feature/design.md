# Design: Preferences Feature

## Target

[P0][架构预备] 当面板读取或修改 accent、density、expanded size、top offset 时，系统应该通过 `PreferencesFeature` 维护 Swift preferences/theme 投影，而不是让 `TaskCoordinator` 直接拥有 `PreferencesCore`。

## Current Evidence

`TaskCoordinator` 目前仍直接持有 `PreferencesCore`，并内联：

- 初始 `uiPreferences()` 读取。
- `setAccent` 后同步 `preferences`、`theme.accent`、`layoutPreferencesDidChange`。
- `setDensity` 后同步 `preferences`、`theme.accent`、`layoutPreferencesDidChange`。

这和其他已抽出的 feature owner 不一致。它也是 coordinator 里最后一个直接 core 协议字段。

## Component Contract: `PreferencesFeature`

- Responsibility：维护 UI preferences 和 theme 的 Swift 投影；把 accent/density intents 转发给 `PreferencesCore`；暴露更新后的 preferences/theme。
- Not responsible for：不持久化到磁盘；不修改系统设置；不移动 panel；不决定 SwiftUI 控件展示。
- Owner：Swift feature-store 层拥有 preferences/theme projection；C++ core 仍拥有 in-memory preference policy 和 sizing rules。
- Interface：
  - `preferences`
  - `theme`
  - `setAccent(_:) -> ConsolePreferences`
  - `setDensity(_:) -> ConsolePreferences`
- State：`preferences` 是 core 返回的当前偏好投影；`theme` 是由 preferences accent 派生的 UI theme。
- Side effects：只调用 `PreferencesCore`; layout callback 仍由 coordinator 兼容层触发。
- Invariants：
  - 初始化时 preferences/theme 必须来自 core snapshot。
  - accent 更新后 preferences.accent 和 theme.accent 必须一致。
  - density 更新后必须保留 core 返回的 panel size 和 top offset。
  - feature 不直接触发 AppKit layout callback。
- Lifecycle：`TaskCoordinator` 初始化 feature，并同步公开投影给 SwiftUI 和 AppKit controller。
- Test surface：direct smoke 通过 feature 公开接口和 coordinator 公开状态验证。

## Validation Strategy

- Direct smoke:
  - `PreferencesFeature` 初始化后暴露默认 accent、density、expanded size。
  - `setDensity(.compact)` 后 size 来自 core。
  - `setAccent(.amber)` 后 preferences/theme accent 一致。
  - `TaskCoordinator` 兼容路径仍触发 layout callback。
- Existing smoke:
  - `scripts/test.sh` 覆盖 direct tests 和 app bridge smoke。
  - `scripts/build.sh` 确认 app target 编译。
  - `openspec validate --all --strict` 保持 specs 一致。

## Design Review

- 业务语义：通过。只移动 preferences/theme owner，不改变 UI 行为。
- 架构边界：通过。C++ core 保持 preference policy owner，Swift feature 只拥有投影。
- 组件契约：通过。layout callback 留在 coordinator/app shell 兼容边界。
- 任务可验证性：通过。feature 和 coordinator 兼容路径都有 direct smoke。
- `chowa/skill-gaps.md`：无新增。
