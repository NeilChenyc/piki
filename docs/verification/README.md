# 验证目录

这个目录用于维护 Piki 的专项验证文档。

原则：

- 每个专项只保留极简信息
- 必须定位到脚本
- 必须说明设计目标和 case 来源
- 不在这里重复记录长篇分析

## 专项列表

| 专项 | 设计目标 | 脚本 / 真相源 | 文档 |
| --- | --- | --- | --- |
| Agent 回归 | 验证统一 Agent task 在 query / record / ingest / lint 等典型场景下的行为 | [scripts/run_agent_regression.py](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/scripts/run_agent_regression.py), [docs/development/agent_regression_cases.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/development/agent_regression_cases.json) | [agent-regression.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/verification/agent-regression.md) |
