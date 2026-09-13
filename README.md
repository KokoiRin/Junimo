# Junimo

一个住在 Mac 刘海旁边的轻量 Codex 伴侣。

Junimo 让你不打开 Codex 也能快速看到剩余用量。任务完成时，它会播放提示音并显示可点击的任务横幅；展开刘海面板后，还可以看到最近完成的任务，并直接打开自己配置的常用网站或应用。

## 你能用它做什么

- 在刘海旁随时查看 Codex 剩余用量。
- Codex 任务完成时播放 `Hero` 提示音，不必一直盯着窗口。
- 点击完成横幅，直接回到对应的 Codex 任务。
- 展开面板后查看任务提醒是否可用，以及最近完成的任务。
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

1. 启动 Junimo 后，刘海左侧显示 Codex 剩余用量，右侧默认显示常用应用图标栏。
2. 将鼠标移到屏幕顶部中央，展开 Junimo 面板。
3. 展开后的标题下方会显示任务提醒连接状态；有新任务完成时，会显示最近完成的任务名称。
4. 点击“快速打开”中的入口，打开对应网站或应用。
5. Codex 任务完成时，点击 Junimo 横幅可以返回对应任务。
6. 点击菜单栏中的 Junimo 图标，可以管理常用应用、显示面板、编辑快捷入口或退出应用。

## 常用应用切换栏

在 Junimo 菜单中选择“管理常用应用…”即可添加本机应用、移除或上移/下移排序，最多收藏 12 个。细绿色描边和淡底色标记当前前台应用；点击图标打开或切换，悬停显示名称。前台应用不在当前展示图标中时，不显示选中标记。

试用 Command＋双指左右滑动：缺少授权时，从 Junimo 菜单选择“恢复 Command＋双指滑动切换…”，直接进入系统辅助功能设置并允许 Junimo。Junimo 每两秒检查一次，授权后自动连接，无需重启；监听器失效时自动重建，不额外弹出引导窗口。手势可从菜单关闭。

应用栏显示至少两个图标时，鼠标在其他应用上也能按住 Command 双指横滑，向左或向右切换一个可见图标，首尾循环；每次需抬起手指再滑，惯性不会再次触发。切换直接复用点击行为，未运行应用会启动，“更多”里的图标不参与。普通滚动、竖滑、应用栏隐藏或管理窗口打开时不接管手势。正在打开应用时忽略额外切换，防止重复启动。

本机开发可运行一次 `scripts/setup_local_signing.sh` 配置固定签名：该脚本生成 Junimo 专用自签名证书，将私钥导入当前用户默认钥匙串，只为代码签名用途建立当前用户信任，随后删除磁盘私钥。证书和身份指纹保存在 `~/Library/Application Support/Junimo/signing`，后续构建自动复用；重新运行不会生成新的身份。首次从临时签名迁移仍需重新授权。此配置会持久化修改钥匙串，运行前应确认接受；它不会自动开启辅助功能权限，也不用于应用分发或公证。若已有签名身份，可用 `JUNIMO_SIGNING_IDENTITY` 指定。没有固定身份时保留临时签名并在构建中提示，签名失败则停止构建，避免静默生成身份改变的应用。

首次签名时，系统可能要求允许 `codesign` 使用“Junimo Local Development”私钥；可在系统弹窗选择“始终允许”以供后续构建复用。构建后运行 `scripts/verify_local_signing.sh`，它修改并重新签名一个临时应用副本，确认内容哈希变化后仍保持相同身份，并满足原版本的签名要求；不启动测试副本或操作辅助功能权限。

应用栏固定显示在刘海右侧，“显示应用栏”可临时关闭。最多直接展示 4 个应用，超出的应用进入“更多”。右侧空间不足时会进一步收起图标；仍需在实际屏幕上确认没有与其他菜单栏图标冲突。展开 Junimo 大面板时应用栏暂时隐藏。

常用应用由 Go 后端保存到 `~/Library/Application Support/Junimo/app-shortcuts.json`，首次只导入旧快捷配置中的应用项目。之后独立管理；清空后保持为空，原有网页快捷入口仍留在展开面板。显示开关由 macOS 偏好设置保存。切换应用使用系统打开动作，具体多窗口、最小化恢复和跨桌面行为由 macOS 与目标应用决定。

本机协议 v6 增加 `GET/PUT /app-shortcuts`；PUT 使用 JSON `{"revision":1,"items":[{"bundleId":"com.openai.codex","name":"Codex"}]}`，并携带当前启动实例的 `X-Junimo-Instance-ID`。保存前先 GET 获取最新 `revision`；旧版本写入返回 409，未提供版本返回 428，防止覆盖其他修改。界面每秒同步后端收藏，发生保存冲突时刷新列表并提示重新操作。

`POST /app-shortcuts/selection` 接收同一实例的 JSON `{"revision":1,"visibleCount":3,"activeId":"com.openai.codex","direction":1}`，方向为 `-1` 或 `1`。后端在当前收藏的可见前缀中选出相邻应用，返回 `{"item":...}`；空栏返回 `{"item":null}`，过时版本返回 409。该接口不修改收藏，也不执行应用打开动作。

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
