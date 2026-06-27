# Tasks

- [x] 1. 增加 runtime composition smoke test，先证明当前缺少 `JunimoRuntime` 组合入口。
- [x] 2. 实现 `JunimoRuntime`，组合 coordinator、提醒投递、Codex monitor 和健康诊断。
- [x] 3. 收敛 `AppDelegate`，让它通过 runtime 启停产品 wiring，只保留 AppKit surface 职责。
- [x] 4. 更新 test harness 编译入口，覆盖 runtime app smoke test。
- [x] 5. 更新架构文档、机会池和 OpenSpec spec。
- [x] 6. 运行 `scripts/test.sh`、`scripts/build.sh`、`openspec validate --all --strict`、`git diff --check`，归档完成的 change。
