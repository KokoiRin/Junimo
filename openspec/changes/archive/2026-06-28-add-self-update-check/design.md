# Design: Self Update Check

## Context

Junimo 现在已经能通过 GitHub Release 安装最新版：`scripts/install_latest.sh` 会下载稳定命名的 `Junimo-macos-arm64.zip`，复制 `Junimo.app` 到 `/Applications` 或 `~/Applications`，并重新打开应用。这个路径适合首次安装，也可以被外部更新器复用。

缺口在已安装用户侧：应用不知道当前版本和 GitHub 最新 release 的关系，菜单栏没有可发现的新版本状态，也没有能直接更新的按钮。上一版草稿把菜单按钮直接连到更新脚本，这是错误边界：它跳过了版本检查，也让 `AppDelegate` 承担了发布流程细节。

## Goals / Non-Goals

**Goals:**

- 用户手动选择 `Check for Updates...` 时执行一次即时检查，并根据结果把菜单更新为“已是最新 / 检查失败 / 可更新”。
- 如果实现成本低，Junimo 启动后自动做一次后台检查；后台检查只更新菜单状态，不弹窗、不安装。
- 只有当最新 release 版本高于当前 bundle 版本，且用户点击更新按钮时，系统才启动安装。
- 安装由外部 updater 进程完成：当前 app 可以退出，updater 覆盖当前安装目录中的 `Junimo.app` 并重新打开。
- 更新检查、状态转换、安装副作用都有测试接缝，避免 UI 层和 shell 脚本成为唯一验证方式。

**Non-Goals:**

- 不接入 Sparkle，不做增量更新、自动静默安装、后台下载缓存或 release notes 渲染。
- 不做签名、公证、校验和或二进制验签；本轮沿用现有 GitHub HTTPS release 安装通道。
- 不支持多架构选择；继续沿用当前 Apple Silicon release asset。
- 不做确认弹窗、release notes 弹窗或复杂更新窗口；第一版只保留菜单按钮。
- 不要求第一版必须长期定时轮询；手动检查必须可用，启动后自动检查作为低成本增强。
- 不改变 GitHub Release 发布 workflow 的整体结构；只要求 bundle 版本和 tag 保持可比较。

## Decisions

### 1. 新增 `SelfUpdateFeature` 作为更新状态 Owner

新增纯状态模型放在 `JunimoCore`，由 `TaskCoordinator` 兼容暴露给 app shell。

- `ReleaseVersion`：解析 `v0.1.5` / `0.1.5`，按数字段比较。
- `SelfUpdateSnapshot`：
  - `currentVersion`
  - `latestVersion`
  - `state`: `idle | checking | upToDate | updateAvailable | checkFailed | installing | installFailed`
  - `message`
  - `lastCheckedAt`
- `SelfUpdateFeature`：负责从“当前版本 + release check result + install result”推导快照。

原因：版本比较和状态转换是业务规则，必须可单测；如果藏在 `AppDelegate` 或脚本里，后续任何 UI/安装改动都会破坏语义。

替代方案：只在菜单点击时跑 shell 脚本重装。放弃，因为它无法判断是否需要更新，也难以测试“不更新同版本/旧版本”的核心规则。

### 2. runtime 拥有 `SoftwareUpdateService` 生命周期

新增 app/runtime 层服务：

- Responsibility：响应手动检查，并可在启动后低成本触发一次 release check，将结果写回 coordinator 的 self-update 状态。
- Inputs：当前 bundle 版本、release checker、timer/scheduler、coordinator sink。
- Outputs：更新后的 `SelfUpdateSnapshot`，以及菜单可读状态。
- Side effects：网络请求由 checker 负责；timer 由 service 负责。
- Not responsible for：不展示 NSAlert，不直接执行安装。

`JunimoRuntime` 创建并 start/stop 该服务；`AppDelegate` 只从 runtime/coordinator 读取状态和触发用户 intent。

检查频率：第一版至少支持手动检查；如果实现成本低，启动后延迟一次检查。暂不做长期轮询，避免把本轮范围扩大成完整 auto-update 系统。

替代方案：用 LaunchAgent 或外部 cron 检查。放弃，因为 self-update 是 app 内用户体验，状态应归属于运行中的 app。

### 3. release checker 读取 GitHub latest release 元数据

新增 `GitHubReleaseChecker`，默认读取 `https://api.github.com/repos/KokoiRin/Junimo/releases/latest`，解析 `tag_name`，并形成 `ReleaseInfo(version:assetName:url:)`。

规则：

- 只接受可解析的稳定版本 tag，例如 `v0.1.5`。
- 如果最新版本小于或等于当前版本，状态为 `upToDate`。
- 如果网络失败、JSON 不合法、版本不可解析或缺少 release asset，状态为 `checkFailed`。

原因：版本检查需要知道最新 tag；现有 `latest/download/Junimo-macos-arm64.zip` 只能下载资产，不能判断是否需要下载。

替代方案：请求 GitHub `/releases/latest` 重定向并解析 URL。可行但更脆弱；API JSON 更适合测试和后续扩展 release notes。

### 4. 菜单负责用户意图，不负责更新决策

状态栏菜单增加：

- 默认：`Check for Updates...`
- 有新版本：`Install Update...`

用户点击后：

1. 如果状态已经是 `updateAvailable`，菜单显示 `Install Update...`，点击后直接启动外部 updater。
2. 如果状态未知或过期，先执行一次手动检查。
3. 无新版本时菜单可短暂显示 `Junimo is Up to Date` 或保持 `Check for Updates...`。
4. 检查失败时菜单可短暂显示失败状态，并允许再次点击检查。

第一版不弹确认框。用户看到 `Install Update...` 并点击，即表达安装意图。

### 5. 安装由外部 updater 进程完成

新增或调整 `scripts/update_latest.sh` 作为外部 updater：

- 读取 `JUNIMO_INSTALL_DIR`，优先更新当前 app 所在目录。
- 终止正在运行的 Junimo 进程。
- 调用或复用 `install_latest.sh` 下载最新 release zip。
- 替换 `Junimo.app` 并重新打开。

app 触发安装时启动 detached `/bin/bash` 进程运行 updater，然后退出自身。安装成功与否不由当前 app 同步等待；失败日志进入 updater 输出，下一次启动或用户重试时重新检查。

原因：运行中的 macOS app 覆盖自身风险高；外部进程是最小可靠边界。

替代方案：App 内直接下载并复制 app bundle。放弃，因为会让 AppDelegate/runtime 承担大量文件系统和生命周期副作用。

## Component Contract: `SelfUpdateFeature`

- Responsibility：拥有更新状态和版本比较业务规则。
- Not responsible for：不做网络请求，不展示 UI，不运行 shell，不读写 app bundle。
- Owner：`JunimoCore` feature state，`TaskCoordinator` 作为兼容 facade 暴露。
- Interface：
  - `startChecking(now:)`
  - `applyReleaseCheck(result:now:)`
  - `startInstalling(now:)`
  - `applyInstallFailure(message:now:)`
  - `snapshot`
- State：`SelfUpdateSnapshot` 是唯一权威源；菜单 title 和 alert 文案都是派生投影。
- Side effects：无。
- Invariants：
  - 最新版本小于或等于当前版本时不得进入 `updateAvailable`。
  - 未完成成功版本检查时不得进入 `installing`。
  - `installing` 只能由用户点击更新按钮触发，后台检查不得触发安装。
- Lifecycle：runtime 初始化时创建；service/checker 回调推动状态变化；app 退出时无需持久化。
- Test surface：通过公开 feature/coordinator 方法验证快照状态。

## Component Contract: `SoftwareUpdateService`

- Responsibility：调度手动检查，并可在启动后触发一次自动检查，把 release checker 结果写回 coordinator。
- Not responsible for：不展示 modal，不执行安装，不比较版本业务规则。
- Owner：`JunimoRuntime`。
- Interface：
  - `start()`
  - `stop()`
  - `checkNow(reason:)`
- State：只保存 timer/service lifecycle；更新业务状态在 `SelfUpdateFeature`。
- Side effects：timer 和网络 checker 调用。
- Invariants：
  - 同一时间最多一个检查请求在飞行。
  - stop 后不得继续写入 coordinator。
  - 后台检查失败不自动弹窗、不启动安装。
- Test surface：fake checker + fake scheduler 验证手动检查、启动后自动检查和 stop 后不回写。

## Component Contract: `ExternalUpdateInstaller`

- Responsibility：在用户点击更新按钮后启动外部 updater，并传入当前安装目录。
- Not responsible for：不判断是否有新版本，不下载 release JSON，不展示确认 UI。
- Owner：app/runtime adapter。
- Interface：
  - `installLatest(from installDirectory:) throws`
- State：无长期状态。
- Side effects：启动 detached shell process；当前 app 随后退出。
- Invariants：
  - 只能在 `SelfUpdateSnapshot.state == updateAvailable` 后被调用。
  - 必须传入当前 bundle 的父目录，避免误装到另一个位置。
  - 启动失败要回写 `installFailed`，不能让 UI 以为已经开始更新。
- Test surface：fake installer 验证安装 intent 包含正确 install directory，不验证真实文件替换。

## 可执行测试计划

- S1：当 latest release 版本高于当前版本时，系统应该进入 updateAvailable。
  - 业务语义 / 不变量：只有真正的新版本才呈现更新入口。
  - 验证方式：L1
  - 测试入口：`Tests/JunimoDirectTests/main.swift` / `SelfUpdateFeature`
  - 测试名：`self update marks newer release as available`
  - 中文注释：`业务语义：最新 release 版本高于当前 bundle 版本时，菜单才能显示可安装更新。`
  - 夹具 / harness / fake / mock：构造 current `0.1.4` 和 latest `v0.1.5`。
  - 预期断言：snapshot state 为 `updateAvailable`，latestVersion 为 `0.1.5`。

- S2：当 latest release 版本小于或等于当前版本时，系统不得提示安装。
  - 业务语义 / 不变量：同版本或旧版本不能触发重装。
  - 验证方式：L1
  - 测试入口：`Tests/JunimoDirectTests/main.swift` / `SelfUpdateFeature`
  - 测试名：`self update treats equal or older release as up to date`
  - 中文注释：`业务语义：版本比较必须保护用户不被同版本或旧版本更新打扰。`
  - 夹具 / harness / fake / mock：构造 equal 和 older release。
  - 预期断言：snapshot state 为 `upToDate`，不可安装。

- S3：当检查失败时，系统应该记录失败状态但不启动安装。
  - 业务语义 / 不变量：网络或 release 元数据失败不能变成更新 intent。
  - 验证方式：L1/L2
  - 测试入口：`Tests/JunimoAppDirectTests/main.swift` / `SoftwareUpdateService` fake checker
  - 测试名：`self update records check failure without installing`
  - 中文注释：`业务语义：检查失败只影响更新状态，不允许自动进入安装流程。`
  - 夹具 / harness / fake / mock：fake checker 返回 failure，fake installer 记录调用次数。
  - 预期断言：state 为 `checkFailed`，installer 调用次数为 0。

- S4：当用户点击可用更新按钮时，系统应该只启动外部 updater 一次并传入当前安装目录。
  - 业务语义 / 不变量：安装必须由用户点击更新按钮触发，并更新当前安装位置。
  - 验证方式：L2
  - 测试入口：`Tests/JunimoAppDirectTests/main.swift` / runtime or update command handler
  - 测试名：`self update starts installer after user clicks update`
  - 中文注释：`业务语义：用户点击更新按钮后，app 只负责启动外部 updater，真实替换由 updater 完成。`
  - 夹具 / harness / fake / mock：fake installer、fake bundle install directory。
  - 预期断言：installer 收到当前 app 父目录，state 进入 `installing`。

- S5：runtime 启动后应该拥有更新检查服务生命周期。
  - 业务语义 / 不变量：更新检查属于 runtime wiring，不属于 AppDelegate 临时逻辑。
  - 验证方式：L2
  - 测试入口：`Tests/JunimoAppDirectTests/main.swift` / `JunimoRuntime`
  - 测试名：`runtime starts and stops software update service`
  - 中文注释：`业务语义：runtime 是后台服务生命周期 owner，AppDelegate 只处理 AppKit surface。`
  - 夹具 / harness / fake / mock：fake update service 或 fake checker/scheduler。
  - 预期断言：runtime start 触发一次检查，stop 后不再回写。

## Risks / Trade-offs

- GitHub API 失败或 rate limit → 手动检查显示失败，后台检查静默降级；后续可加缓存或使用 release manifest。
- `curl | bash` 更新路径安全性有限 → 本轮沿用现有安装通道；正式公开分发前应切到签名/公证 + Sparkle 或验签 manifest。
- 当前 app 无法同步知道外部 updater 是否成功 → 安装开始后退出；新 app 启动后再通过版本检查确认状态。
- 用户没有写入 `/Applications` 权限 → `install_latest.sh` 现有逻辑可 fallback 到 `~/Applications`，但用户从 `/Applications` 运行时应优先提示权限/失败而不是静默装到别处；实现时需要明确保留当前安装位置优先级。

## Migration Plan

1. 先实现纯 `SelfUpdateFeature` 和版本比较测试。
2. 再接手动检查服务和 fake-backed runtime 测试。
3. 最后接菜单按钮和外部 updater；启动后自动检查作为低成本增强一并接入。
4. 发布时 bump bundle 版本到 `0.1.5` 并创建 tag；旧版本用户检查到 `v0.1.5` 后可以点击更新。

Rollback：如果 release 后更新流程有问题，可以删除或隐藏菜单入口；现有手动 `install_latest.sh` 安装路径仍可使用。

## Design Review

- 业务语义：通过。设计明确区分检查、菜单更新按钮和安装。
- 架构边界：通过。core owns 状态规则，runtime owns 服务生命周期，AppDelegate 只做菜单入口。
- 组件契约：通过。`SelfUpdateFeature`、`SoftwareUpdateService`、`ExternalUpdateInstaller` 的 owner、状态、副作用和不变量清楚。
- 任务可验证性：通过。核心版本规则和 runtime wiring 都有 fake-backed 测试计划；真实安装走脚本静态/手动验证。
- `chowa/skill-gaps.md`：无新增。
