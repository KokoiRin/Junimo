# Design: 手动截图采集与今日统计

## 核心行为语义

当用户需要截图采集时，应该在终端手动运行 `scripts/run_activity_capture_manual.sh`；Junimo 主面板截图页只读取今天的采集目录并统计现有文件，不依赖 LaunchAgent、后台服务或权限状态。

## 业务语义

- 手动脚本以前台循环运行，每轮调用 `capture_activity_snapshot.py`。
- 截图权限归属于启动脚本的终端/Python 进程。
- 统计页读取 `~/Documents/JunimoActivityCaptures/<yyyy-mm-dd>/`。
- 统计字段包括：图片数、index 行数、有效 indexed 文件数、缺失 indexed 文件数、总字节数、最新文件。
- 有效 indexed 文件只表示 index 行对应文件存在且 width/height/bytes 为正；本轮不判断图片内容是否黑屏或语义无效。

## 架构边界

新增 `ActivityCaptureStatsFeature` 作为统计状态 owner。它只读文件系统，不启动进程、不安装服务、不申请权限。`TaskCoordinator` 暴露 `activityCaptureStats` 给 SwiftUI，并以低频刷新避免 UI timer 每 tick 扫描文件系统。

## 验证策略

- Direct smoke test 用临时目录构造当天图片和 `index.csv`，验证统计口径。
- App smoke test 验证截图页面 copy 指向手动脚本，并且不再提 LaunchAgent。
- `rg` 静态检查确认运行时文档和源码没有旧 LaunchAgent 入口。
