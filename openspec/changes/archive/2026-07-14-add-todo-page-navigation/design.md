## Context

Junimo 当前由 Swift/AppKit 外壳和独立 Go HTTP 后端组成。Swift 负责刘海窗口、悬停展开和渲染；Go 负责番茄钟、Codex 适配和产品快照。展开面板目前是固定 `420×236` 的单页番茄钟，Swift 到 Go 的意图接口也只接受番茄钟动作。

旧版 `9cca59f` 曾在 SwiftUI 中使用左侧 `pageTabs` 和右侧页面，并通过 C++ core 持久化 Corner Note/Todo。该实现证明了交互形态，但旧功能树、C++ bridge 和独立角落便签已退出活跃构建，本次只借鉴导航与行编辑语义。

## Goals / Non-Goals

**Goals:**

- 建立可继续增加平级工具的展开面板容器。
- 让番茄钟和 Todo 保持独立，页面切换不改变任何产品状态。
- 让 Go 成为 Todo 正式数据、规则和持久化的唯一事实源。
- 让 Swift 只维护页面选择、输入草稿、焦点和悬停等壳层状态。
- 通过组合快照、类型化意图和单调 revision 保持跨进程一致性。
- 保留现有番茄钟完成事件到 macOS 通知的边界。

**Non-Goals:**

- 不让 Go 感知 Tab、侧栏、页面尺寸、SwiftUI 或 AppKit。
- 不恢复旧 Corner Note、Reminder、Capture、Codex 线程页或 C++ bridge。
- Todo 不包含截止时间、提醒、标签、优先级、子任务、拖动排序或云同步。
- 不把 Todo 与番茄钟会话关联。

## Decisions

### 1. 页面选择由 Swift 持有，不经过 Go

页面选择只决定壳层当前渲染哪个平级功能，没有独立业务结果。`JunimoSurfaceView` 保存 `PanelPage.focus/todo`，Tag 点击直接改变该值；选中态和右侧页面从同一值派生。收起再展开保留本次应用会话的选择，重新启动默认专注页。

备选方案是 Swift 把点击意图发给 Go，由 Go 返回 `activeFeature`。该方案被否决，因为它让后端认识 UI 导航结构，使 Go 不可用时连本地页面都无法切换，并为每次点击增加无业务价值的跨进程往返。Go 控制产品规则，不控制 AppKit 壳层导航。

### 2. Todo 是独立 Go 领域，Swift 不做乐观正式状态

Go 新增 `backend/internal/todo`，维护有序任务集合。任务包含稳定 ID、规范化标题和 `open/completed` 状态。创建、重命名、设置完成状态和删除都先在 Go 校验，持久化成功后才替换正式状态并返回新快照。

Swift 只保存未确认的输入草稿。用户确认后发送类型化意图，并等待 Go 快照更新列表；失败时保留草稿或原有快照，不能伪造已保存结果。

### 3. 完成操作使用目标状态而非 toggle

HTTP 意图使用 `todo.setCompletion(id, completed)`，不使用 `toggle`。重复请求因此幂等，不会因重试或重复点击把任务翻回相反状态。

### 4. Todo 持久化使用可注入 Store 与原子文件替换

Go 领域依赖最小 `Store` 接口，生产实现写入用户 Application Support 下的 Junimo Todo 文件，测试使用临时目录或内存 fake。保存先写同目录临时文件，再 rename 替换；只有保存成功，内存候选状态才生效。不存在的文件等价于空列表，损坏或不可读文件使 Todo 快照进入 unavailable，但不阻止番茄钟和 `/state` 服务。

### 5. 扩展统一产品意图和组合快照

Swift 将当前 `PomodoroIntent` 专用传输入口提升为 `ProductIntent`，内部包含 `PomodoroIntent` 与 `TodoIntent`。Go 的 `/intent` adapter 严格校验每种 JSON 形状，再路由到相应领域。`/state` 增加 Todo 快照并递增协议版本；Todo 与 Pomodoro 只在组合层并列，不互相依赖。

### 6. 文本编辑是可保持展开的 Swift 交互会话

Swift 跟踪指针是否在面板内以及 Todo 编辑是否活跃。指针离开且没有编辑会话时收起；编辑期间保持展开，结束编辑后若指针已离开再收起。当前 `JunimoPanel.canBecomeKey == false` 需要调整为允许文本控件获取键盘和输入法焦点，但面板仍不成为主窗口。

### 7. 展开布局拆为容器、导航与独立页面

展开尺寸调整为约 `560×320`，左侧约 96pt 导航，右侧约 420pt 页面。专注页复用现有计时和控制行为；Todo 页提供新增输入、未完成列表、折叠的已完成列表、行内编辑和删除。折叠态双胶囊和 Codex 用量保持不变。

## Risks / Trade-offs

- **TextField 在 nonactivating NSPanel 中无法稳定获取输入法焦点** → 允许 panel 成为 key，并用 Swift 状态锁住编辑会话；增加直接状态测试和 App Bundle 构建验证。
- **持久化失败造成内存与磁盘分叉** → 候选状态先原子保存，成功后再替换内存状态；失败响应不发布新列表。
- **统一意图后错误 JSON 组合变多** → HTTP adapter 对每种意图严格拒绝缺字段、未知字段和无关字段，并补表驱动契约测试。
- **展开面板增大导致圆角或屏幕定位回归** → 保持顶边锚定，更新离屏圆角回归和窗口尺寸断言。
- **旧实现诱导恢复过多功能** → 旧 C++/Swift 只作证据，活跃代码范围仍限制在 `Sources/JunimoShell`、`Sources/JunimoShellCore` 和 `backend`。

## Migration Plan

1. 先增加 Go Todo 领域、Store 和行为测试，不改变 Swift。
2. 扩展后端组合快照与意图契约，并把协议版本提升到 4。
3. 扩展 Swift DTO、产品意图和 ShellState，通过真实 Swift-Go 契约测试。
4. 重组展开 UI、窗口尺寸与文本编辑生命周期，保持折叠态不变。
5. 完整验证后更新 README；若需要回滚，删除 Todo 字段/意图和多页面 UI，并把协议版本恢复到上一版。

## Open Questions

无。第一版默认新任务置顶、标题最长 120 个字符、允许重名、启动默认专注页，已完成任务保留到主动删除。
