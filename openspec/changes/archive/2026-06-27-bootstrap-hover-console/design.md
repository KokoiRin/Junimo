## Context

当前仓库是空的 Git 仓库，需要从零建立 macOS 原生桌面工具。第一版必须优先证明一个完整交互链路可构建、可运行、可测试：顶部中央小胶囊、hover 展开、展示 mock agent/动作/活动、点击动作后通过协调层更新状态、鼠标离开后延迟收起。

技术约束是 Swift + SwiftUI，必要的窗口行为用 AppKit；不引入 Electron、Tauri、WebView、C++ 或真实 Agent 协议。UI 不直接执行 shell 或系统操作。

## Goals / Non-Goals

**Goals:**
- 建立 SwiftPM 项目，包含可运行 macOS executable 和可单测核心 library。
- 用 AppKit 创建非抢焦点、浮动、顶部中央定位的窗口容器，用 SwiftUI 渲染胶囊/控制台。
- 用 `TaskCoordinator` 作为 UI 到执行层的唯一入口。
- 用 mock adapter 提供 agent、快捷动作、项目动作和最近活动的第一版行为。
- 提供基础主题状态。
- 提供番茄钟创建、取消、完成和提醒请求的核心行为。
- 写入 README 或 `docs/progress.md`，保留构建、测试、运行方式和已知问题。

**Non-Goals:**
- 不接入真实 Codex、Hermes、终端命令或系统快捷动作。
- 不做菜单栏 App、偏好设置窗口、登录项、沙盒签名或打包安装。
- 不做复杂真实通知权限流；第一版只在核心层表达“需要提醒”，UI/系统通知后续可替换接入。
- 不持久化状态，不做复杂主题编辑器。

## Decisions

1. **SwiftPM 双 target：`JunimoCore` + `Junimo`**
   - `JunimoCore` 放置 `TaskCoordinator`、adapter 协议、mock adapter、agent/action/activity 模型、番茄钟状态机和主题模型。
   - `Junimo` 是 executable target，负责 `NSApplicationDelegate`、`NSPanel` 生命周期和 SwiftUI view。
   - 备选 Xcode project 更接近标准 `.app` 打包，但从空仓库启动时 SwiftPM 更轻，能立即 `swift build`/`swift test` 验证。

2. **AppKit host + SwiftUI content**
   - 使用 `NSPanel` 的 `.nonactivatingPanel`、`.fullSizeContentView`、`.floating` 层级，定位到主屏幕顶部中央。
   - SwiftUI view 只接收 `TaskCoordinator` 状态和调用公开方法，不直接触碰 AppKit 或 shell。
   - hover 进入立即展开，hover 离开后由协调器延迟收起，避免窗口/视图层散落计时逻辑。

3. **Adapter-first mock execution**
   - `TaskExecutionAdapter` 定义 action 执行接口。
   - 第一版 `MockTaskExecutionAdapter` 只返回结构化结果，不执行外部副作用。
   - 点击 action 后 `TaskCoordinator` 根据结果更新 agent 状态和最近活动。

4. **番茄钟用可注入 clock/scheduler 的轻量状态机**
   - 第一版不依赖真实 wall-clock 单测等待；核心方法支持创建、取消、tick/完成检查。
   - 完成时返回或记录 notification request，系统通知 adapter 后续接入。
   - UI 提供创建和取消入口，默认 25 分钟，可用短 preset 方便开发验证。

## Risks / Trade-offs

- **SwiftPM executable 不是完整打包 `.app`** → 先保证构建/运行链路，后续需要发布时再补 Xcode project 或 bundle 脚本。
- **非抢焦点窗口行为依赖 macOS 权限/版本细节** → 第一版用标准 `NSPanel` 配置，并把限制记录到 progress 文档。
- **真实系统通知未接入** → 核心先产生可测试 notification request，避免把权限流提前塞进主链路。
- **hover 离开后的收起在自动化测试中难以完整 UI 验证** → 核心协调器单测覆盖延迟收起决策，手动运行验证窗口行为。
