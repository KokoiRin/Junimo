# Skill Gaps

## 判断原则缺口

- 问题：项目已有多个历史 active OpenSpec change，但没有主 `openspec/specs/` 目录；Chowa 归档前应先归档全部已完成历史 change，还是只归档本轮相关 change？
  推荐答案：当用户明确要求清理过期状态时，可以一次性归档所有 09 检查可归档的历史 change；否则只归档本轮相关 change。
  后续是否需要补进 Skill：是，可以在 10 阶段补充“存在历史未归档 change 时的范围选择”。

## 运行反馈

- 阶段：01 / 09
  现象：用户目标是项目基线对齐，仓库又已有半成品实现和文档 diff；直接进入完整 propose 会重复已有 artifacts。
  本轮处理：按半成品入口执行目标发现和完成检查，只补齐 Chowa 机会池、harness 说明和过期 README 表述。
  建议改进：在 Chowa 主流程中增加“基线对齐 / readiness audit”分支，明确这类任务默认不重新 propose。
