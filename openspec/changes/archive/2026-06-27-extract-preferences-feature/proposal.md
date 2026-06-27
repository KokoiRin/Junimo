# Change: 抽出 Preferences Feature

## Why

`TaskCoordinator` 已经基本退成 feature facade，但 UI preferences 仍然由 coordinator 直接持有 `PreferencesCore` 并处理 accent、density、theme、expanded panel size 同步。偏好是面板基础状态：SwiftUI、NotchPanelController、LaunchHealthReporter 都会读取它。后续要持久化偏好或增加更多显示选项时，如果继续放在 coordinator，会让这个兼容层重新变成状态 owner。

## What Changes

- 新增 `PreferencesFeature`，拥有 `ConsolePreferences` 和 `ConsoleTheme` 的 Swift 投影。
- `TaskCoordinator` 委托 `setAccent`、`setDensity` 给 feature，并继续触发现有 `layoutPreferencesDidChange` callback。
- 增加 direct smoke test，验证 feature 自身和 coordinator 兼容路径。
- 更新机会池和 OpenSpec spec，记录 preferences feature owner 边界。

## Out of Scope

- 不新增磁盘持久化。
- 不改变 UI 控件、布局尺寸或默认偏好值。
- 不修改 macOS 系统设置。
- 不把 preferences 合并到通用 settings framework。
