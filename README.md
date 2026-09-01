# Junimo

一个住在 Mac 刘海旁边的轻量 Codex 伴侣。

Junimo 让你不打开 Codex 也能快速看到剩余用量和任务状态。任务完成时，它会播放提示音并显示可点击的任务横幅；展开刘海面板后，还可以直接打开自己配置的常用网站或应用。

## 你能用它做什么

- 在刘海旁随时查看 Codex 当前状态和剩余用量。
- Codex 任务完成时播放 `Hero` 提示音，不必一直盯着窗口。
- 点击完成横幅，直接回到对应的 Codex 任务。
- 悬停刘海区域，展开常用入口面板。
- 用一个本地 JSON 文件新增、删除和排序网站或应用入口。
- 保存配置后立即刷新，不需要重新构建或重启 Junimo。

## 运行要求

- Apple Silicon Mac
- macOS 14 或更高版本
- [Go 1.26](https://go.dev/dl/)
- Xcode Command Line Tools，其中需要包含 `swiftc`
- 本机已经安装并登录 Codex

可以先检查环境：

```bash
go version
swiftc --version
codex --version
```

## 快速开始

克隆主分支并启动：

```bash
git clone https://github.com/KokoiRin/Junimo.git
cd Junimo
scripts/run.sh
```

`scripts/run.sh` 会构建 Junimo、关闭这个构建目录中的旧实例，然后启动新生成的 App。构建产物位于：

```text
.build/app/Junimo.app
```

如果希望安装到“应用程序”目录：

```bash
scripts/build_app.sh
ditto .build/app/Junimo.app /Applications/Junimo.app
open /Applications/Junimo.app
```

## 下载已构建版本

不想安装开发环境时，可以从 [GitHub Releases](https://github.com/KokoiRin/Junimo/releases/latest) 下载 Apple Silicon 版本。解压后将 `Junimo.app` 拖到“应用程序”目录即可。

当前发布包使用开发者本地签名，尚未经过 Apple 公证。如果 macOS 阻止首次打开，请在 Finder 中右键 Junimo，选择“打开”并确认。

## 日常使用

1. 启动 Junimo 后，刘海两侧会显示 Codex 活动状态和剩余用量。
2. 将鼠标移到屏幕顶部中央，展开 Junimo 面板。
3. 点击“快速打开”中的入口，打开对应网站或应用。
4. Codex 任务完成时，点击 Junimo 横幅可以返回对应任务。
5. 点击菜单栏中的 Junimo 图标，可以显示面板、编辑快捷入口或退出应用。

## 配置快捷入口

Junimo 第一次启动时会生成：

```text
~/Library/Application Support/Junimo/quick-launch.json
```

也可以通过菜单栏的 `Edit Quick Launches…` 直接打开它。默认配置只有 Codex：

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

### 添加一个网站

把下面的对象追加到 `items` 数组中：

```json
{
  "id": "docs",
  "title": "文档",
  "icon": "document",
  "type": "url",
  "target": "https://example.com/docs"
}
```

### 添加一个 macOS 应用

`target` 需要填写应用的 Bundle ID：

```json
{
  "id": "notes",
  "title": "备忘录",
  "icon": "app",
  "type": "application",
  "target": "com.apple.Notes"
}
```

保存文件后，运行中的面板会自动更新。应用升级不会覆盖已经存在的个人配置。

配置需要满足以下规则：

- 每个入口都需要唯一的 `id`，可使用字母、数字、`-` 和 `_`。
- `type: "url"` 只接受 HTTP 或 HTTPS 地址。
- `type: "application"` 的 `target` 必须是应用 Bundle ID。
- 配置文件需要保留 1～12 个入口。
- JSON 写错时，Junimo 会继续显示上一份有效配置；修复并保存后会自动恢复。

<details>
<summary>查看所有图标选项</summary>

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

</details>

## 常见问题

### 看不到 Codex 用量

先确认终端可以找到 Codex：

```bash
codex --version
```

如果 Codex 安装在特殊位置，可以在启动 Junimo 前指定：

```bash
export JUNIMO_CODEX_EXECUTABLE=/path/to/codex
scripts/run.sh
```

### 修改配置后没有更新

检查 `quick-launch.json` 是否仍是有效 JSON。配置错误时，“快速打开”旁会出现橙色警告图标；将鼠标停在图标上可以看到错误原因。

### App 构建或启动失败

运行完整检查：

```bash
scripts/verify_ci.sh
```

它会执行 Go 测试、Swift 行为测试、Swift-to-Go 契约测试、视觉回归和 App Bundle 构建。

## 本地数据

快捷入口配置保存在：

```text
~/Library/Application Support/Junimo/quick-launch.json
```

Junimo 不会把这份个人配置写回代码仓库。删除该文件后，下次启动会重新生成只包含 Codex 的默认配置。

## 开发命令

```bash
scripts/test.sh       # 运行行为、契约和视觉测试
scripts/build_app.sh  # 生成 .build/app/Junimo.app
scripts/run.sh        # 构建并启动
scripts/verify_ci.sh  # 运行完整本地验证
```
