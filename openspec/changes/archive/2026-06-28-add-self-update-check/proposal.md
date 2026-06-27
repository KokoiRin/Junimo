## Why

Junimo 现在只能让用户重新去 GitHub 下载或重新跑安装命令，更新体验仍然像开发工具而不是桌面应用。用户需要已安装的 Junimo 能检查是否有新版本，并在有新版本时通过一个明确按钮完成更新，而不是每次手动找 release。

这个能力现在值得做，因为项目已经有 GitHub Release、稳定命名的 release zip、安装脚本和菜单栏入口；缺口是缺少“版本检查 -> 呈现更新按钮 -> 用户点击安装”的最小产品闭环。

## What Changes

- 新增 Junimo 自更新能力：用户可以从菜单栏检查 GitHub 最新 release 版本；如果实现成本低，应用启动后也可以自动检查一次。
- 当最新 release 版本高于当前应用版本时，Junimo 在菜单栏显示可用更新按钮。
- 用户点击更新按钮后，Junimo 启动外部更新器下载最新 release、替换当前安装位置的 `Junimo.app`，并重新打开应用。
- 当没有新版本、检查失败、安装失败或当前安装位置不可更新时，Junimo 给出明确状态，不静默重装。
- 更新现有 release/install 文档，区分首次安装、检查更新和执行更新。

## Capabilities

### New Capabilities

- `self-update`: Junimo 检查 GitHub Release 版本、呈现可用更新状态，并在用户点击更新按钮后安装新版本。

### Modified Capabilities

- `runtime-composition`: runtime 需要拥有 self-update 服务生命周期，让 AppDelegate 只呈现菜单入口，不直接解析 release 或执行安装逻辑。

## Impact

- App shell：菜单栏增加 `Check for Updates...`，并能根据 self-update 状态呈现更新提示。
- Runtime：新增 self-update service wiring 和测试接缝。
- Core/App models：新增 update 状态、release 版本比较规则和 intent。
- Scripts：保留 `install_latest.sh`，新增或调整外部 update runner，确保 app 进程退出后再替换安装目录。
- Docs：README 和 distribution 文档补充用户更新路径。
- Release：版本号需要随 tag 同步 bump，确保运行时可比较当前版本与最新 release。
