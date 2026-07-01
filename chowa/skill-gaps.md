# Skill Gaps

## 判断原则缺口

- 问题：项目已有多个历史 active OpenSpec change，但没有主 `openspec/specs/` 目录；Chowa 归档前应先归档全部已完成历史 change，还是只归档本轮相关 change？
  推荐答案：当用户明确要求清理过期状态时，可以一次性归档所有 09 检查可归档的历史 change；否则只归档本轮相关 change。
  后续是否需要补进 Skill：是，可以在 10 阶段补充“存在历史未归档 change 时的范围选择”。

## 运行反馈

- 阶段：09
  现象：主面板从单页能力概览改成中文分页模块，影响用户可见行为、测试覆盖和 README/docs，但执行时先按轻量 UI 修改推进，没有同步启动 Chowa 完成检查。
  本轮处理：按用户反馈补走 Chowa 09 完成检查，补齐主面板 page/copy smoke 测试、README 和 architecture/testing 文档。
  建议改进：当 UI 改动改变信息架构、可见文案或导航模型时，即使实现集中在单个 SwiftUI 文件，也应至少进入 Chowa 09 完成检查并同步测试/文档。

- 阶段：01 / 09
  现象：用户目标是项目基线对齐，仓库又已有半成品实现和文档 diff；直接进入完整 propose 会重复已有 artifacts。
  本轮处理：按半成品入口执行目标发现和完成检查，只补齐 Chowa 机会池、harness 说明和过期 README 表述。
  建议改进：在 Chowa 主流程中增加“基线对齐 / readiness audit”分支，明确这类任务默认不重新 propose。
