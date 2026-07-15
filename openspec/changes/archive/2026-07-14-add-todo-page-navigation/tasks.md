## 1. Go Todo 领域与持久化

- [x] 1.1 用先失败的 Go 行为测试固定创建、标题校验、重命名、幂等完成和删除语义
- [x] 1.2 实现独立 Todo 列表模型、稳定 ID、候选状态提交和可注入 Store
- [x] 1.3 用先失败的临时目录测试固定缺失文件、重启恢复、原子保存失败和损坏文件降级
- [x] 1.4 实现 Application Support 文件存储与 unavailable 快照降级

## 2. Go HTTP 组合契约

- [x] 2.1 用先失败的 handler 测试固定 Todo 快照、四种意图形状、非法参数和 Pomodoro 隔离
- [x] 2.2 扩展组合状态和严格意图路由，并把协议版本提升到 4
- [x] 2.3 验证 Todo 存储不可用时 `/health`、`/state`、Pomodoro 和 Codex 仍可使用

## 3. Swift Core 契约与编排

- [x] 3.1 用先失败的 Swift DTO/意图测试固定 Todo 解码、状态枚举和四种请求编码
- [x] 3.2 将后端入口提升为统一 ProductIntent，并扩展 SurfaceState 与 ShellState Todo 操作
- [x] 3.3 用先失败的 ShellState 测试固定 Todo 意图映射、后端快照权威和编辑期间保持展开
- [x] 3.4 扩展真实 Swift-Go 契约测试，验证 Todo 创建到完成及协议版本 4

## 4. 多页面 Swift 壳层

- [x] 4.1 重组展开面板为左侧 Focus/Todo 导航和右侧独立页面，保留折叠双胶囊
- [x] 4.2 把现有番茄钟控件迁入 Focus 页面，不增加 Reminder 卡片或 Go 导航状态
- [x] 4.3 实现 Todo 新增、行内改名、完成/恢复、删除、空态、已完成折叠和错误展示
- [x] 4.4 调整可编辑 NSPanel 生命周期与 `560×320` 展开尺寸
- [x] 4.5 更新离屏视觉测试，固定新面板圆角、导航选中态和 Todo 页面基本布局

## 5. 验证与交付

- [x] 5.1 更新 README 的多页面、Todo 持久化、协议和 Swift/Go 边界说明
- [x] 5.2 运行 `scripts/test.sh`、`scripts/verify_ci.sh`、Go race/vet、OpenSpec validate 和 diff check
- [x] 5.3 按 Warden 检查功能、边界、语义一致性和范围，处理全部阻塞发现
- [x] 5.4 更新 Chowa 计划、决策、验证和归档，并通过 `chowa archive-check`
