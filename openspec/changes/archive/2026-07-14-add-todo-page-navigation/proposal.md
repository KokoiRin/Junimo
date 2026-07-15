## Why

Junimo 的展开面板目前只能承载番茄钟，新增独立工具时缺少稳定的页面容器；旧版曾有多页面导航和 Todo，但其 C++/Swift 功能树已经退出当前构建，不能直接恢复。现在需要在保持 Swift/Go 边界的前提下建立可扩展的功能导航，并交付一个由 Go 拥有数据与规则的简单 Todo 页面。

## What Changes

- 将展开面板改为左侧功能导航、右侧独立页面的容器，第一版提供“专注”和“待办”两个平级页面。
- 页面选择、悬停展开和文本焦点保留为 Swift 壳层状态；切换页面不经过 Go，也不改变任一产品模块状态。
- 保留现有番茄钟行为，只把现有控件迁入专注页面；番茄钟完成通知继续由 Go 完成事件驱动 Swift 平台适配器。
- 新增由 Go 独占状态、校验和持久化的 Todo 列表，支持创建、重命名、设置完成状态和删除。
- 扩展 `/state` 与 `/intent` 契约，使 Swift 只渲染 Todo 快照并发送类型化意图。
- 文本编辑期间保持面板展开；未确认的输入只属于 Swift 草稿，不能成为第二份正式 Todo 状态。
- 不恢复旧 Corner Note、Reminder 卡片、Capture、Codex 线程页或 C++ bridge。

## Capabilities

### New Capabilities

- `feature-navigation`: 展开面板的平级功能导航、页面选择生命周期和模块隔离规则。
- `todo-list`: 本地 Todo 的增删改、完成状态、持久化、失败一致性与 Swift/Go 协作契约。

### Modified Capabilities

无。

## Impact

- Swift 壳层：展开面板布局、页面选择、文本编辑生命周期和窗口尺寸。
- Swift Core：组合快照、统一产品意图、Todo 操作编排和跨进程 DTO。
- Go 后端：新增 Todo 领域与文件持久化，扩展组合快照和 `/intent` 解码。
- 测试：新增 Go Todo 行为/持久化测试、HTTP 契约测试、Swift DTO/状态测试和展开面板视觉回归。
- 协议版本需要递增，因为 `/state` 和 `/intent` 的跨进程契约发生扩展。
