# Junimo

Junimo 是一个轻量的 macOS Codex 伴侣。它常驻在内置屏幕刘海周围，用来展示 Codex 剩余用量、为已完成的 Codex 任务发出声音提醒，并快速打开常用入口，而不会变成另一个任务管理器。

## 当前产品

- 一个透明的顶部中央悬停区域，宽度为 420pt，可跨桌面空间保持可用。
- 折叠状态在刘海两侧显示 Codex 活动胶囊和主用量胶囊。
- 悬停后展开为单个 `560×260` 的伴侣面板。
- 快捷入口默认只包含 Codex，也可以扩展为个人网站或其他 macOS 应用。
- 快捷入口由用户可编辑的 JSON 文件管理，保存后立即重新加载。
- Codex 用量在后台刷新，不会阻塞 `/state`。
- 通过一个长连接 app-server 进程扫描最近的本地 Codex 任务。
- 每个新持久化的成功 Codex turn 都会生成稳定的完成事件。
- 每个完成事件只展示一次可点击的 Junimo 横幅，播放有辨识度的 `Hero` 声音并显示任务标题；点击后会打开对应的 Codex 任务，不依赖系统通知权限。
- 菜单栏入口可以显示面板、编辑快捷入口配置或退出 Junimo。

## 职责边界

- Swift 负责 macOS 外壳：AppKit 生命周期、菜单栏、刘海定位、悬停展开、SwiftUI 渲染、声音提醒和 `NSWorkspace` 打开动作。
- Go 负责 Codex 适配器和产品事实：用量缓存、最近任务监控、完成检测、稳定事件发布和 HTTP 状态接口。
- Swift 只渲染 Go 快照，不直接查询 Codex，也不推断任务是否完成。
- Go 不感知 AppKit 布局、通知展示或应用启动行为。

## 完成检测

Junimo 会建立一条独立的 Codex app-server 连接，并轮询最近的交互任务。第一次成功扫描只建立历史基线，因此启动时不会为旧任务补发提醒。后续状态为 `completed` 的 turn 会以稳定的 Codex turn ID 生成事件；失败或被中断的 turn 会被忽略。

活动监控与用量采集彼此隔离。即使任务监控失败，面板和用量指示器仍会继续工作。

## 后端接口

Go 后端监听 `127.0.0.1:${JUNIMO_BACKEND_PORT:-44832}`。

```text
GET /health
GET /state
```

协议版本 5 的状态示例：

```json
{
  "revision": 12,
  "codex": {
    "status": "available",
    "primary": {
      "remainingPercent": 82,
      "windowDurationMinutes": 300,
      "resetsAt": 1783655023
    }
  },
  "activity": {
    "status": "available",
    "completionEvent": {
      "id": "<turn-id>",
      "threadId": "<thread-id>",
      "title": "任务标题",
      "completedAt": 1783655000
    }
  }
}
```

`revision` 单调递增，Swift 会据此拒绝迟到的旧快照。最新完成事件会保留在后续快照中，Swift 通过事件 ID 去重后再播放提醒。

## Codex 查找

Junimo 会依次检查 `JUNIMO_CODEX_EXECUTABLE`、`PATH`、常见用户安装目录、Codex App Bundle、Homebrew 和 `/usr/local/bin`。候选程序必须可执行，并且能够正确响应 `--version`，才会被采用。

## 快捷入口配置

新安装默认只包含一个 Codex 入口。Junimo 会创建并监听下面这个用户配置文件：

```text
~/Library/Application Support/Junimo/quick-launch.json
```

通过菜单栏的 `Edit Quick Launches…` 可以直接打开它。在 `items` 数组中新增、删除、重命名或调整入口顺序，然后保存；展开面板会自动刷新，不需要重新构建或重启 Junimo。应用升级不会覆盖已经存在的配置文件。如果 JSON 无效，Junimo 会继续使用上一份有效配置，并在“快速打开”旁显示警告图标。

自动生成的默认配置如下：

```json
{
  "iconOptions": ["app", "code", "website", "reading", "document", "tools", "data", "video", "music", "ai", "link"],
  "version": 1,
  "items": [
    {
      "id": "codex",
      "title": "Codex",
      "icon": "code",
      "type": "application",
      "target": "com.openai.codex"
    }
  ]
}
```

### 添加网页

在 `items` 中追加类似下面的对象：

```json
{
  "id": "docs",
  "title": "文档",
  "icon": "document",
  "type": "url",
  "target": "https://example.com/docs"
}
```

### 添加 macOS 应用

将 `type` 设为 `application`，并在 `target` 中填写应用的 Bundle ID：

```json
{
  "id": "notes",
  "title": "备忘录",
  "icon": "app",
  "type": "application",
  "target": "com.apple.Notes"
}
```

### 配置规则

- `type` 支持 `url` 和 `application`。
- `url` 只接受 HTTP 或 HTTPS 网页地址。
- `application` 的 `target` 必须是 macOS 应用的 Bundle ID。
- 每个入口都需要唯一的 `id`，可使用字母、数字、`-` 和 `_`。
- 配置文件必须包含 1～12 个入口。
- 不超过 4 个入口时会均分一行；更多入口会横向滚动。
- 配置写坏时不会清空当前面板，修复并保存后会自动恢复。

### 图标选项

- `app`：通用应用
- `code`：开发工具和终端
- `website`：通用网站
- `reading`：阅读和学习
- `document`：文档和笔记
- `tools`：实用工具
- `data`：数据面板和分析
- `video`：视频网站
- `music`：音乐网站
- `ai`：AI 工具
- `link`：通用链接

## 构建与测试

运行完整本地验证：

```bash
scripts/verify_ci.sh
```

也可以运行范围更小的命令：

```bash
scripts/test.sh
scripts/build_app.sh
scripts/run.sh
```

`scripts/test.sh` 会覆盖 Go 活动与用量行为、Swift DTO 和壳层状态、真实的 Swift-to-Go v5 契约，以及离屏 SwiftUI 视觉回归。最终 App Bundle 会生成在 `.build/app/Junimo.app`。
