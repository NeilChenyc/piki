# Agent 回归

## 设计

| 项目 | 内容 |
| --- | --- |
| 目标 | 验证 Piki 的统一 Agent task 是否满足核心产品预期 |
| 入口 | `POST /tasks` |
| 运行方式 | 真实本地 Agent Service + 临时复制 vault |
| 主脚本 | [scripts/run_agent_regression.py](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/scripts/run_agent_regression.py) |
| Case 真相源 | [docs/development/agent_regression_cases.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/development/agent_regression_cases.json) |
| 输出目录 | [outputs/agent-regression](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression) |
| 默认测试仓库 | [piki-vault](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/piki-vault) |

## Cases

| Case | 意图 | 示例 |
| --- | --- | --- |
| 1 | 普通问候 / 探索式聊天 | 你好，你能做什么？ |
| 2 | 查询知识库事实 | 孟岩正在做点啥？ |
| 3 | 跨页面综合 / 分析 | 我对个人知识库产品的判断是什么？ |
| 4 | 基于回答继续追问 | 展开讲第二点 |
| 5 | 记录对话框中的内容 | 帮我记一下：…… |
| 6 | 上传文件并记录 | 上传文档 + 帮我记录这个文档 |
| 7 | 更新/修正已有 wiki 知识 | 孟岩这页有个地方不对…… |
| 8 | lint | Run vault lint. |

## 运行命令

| 场景 | 命令 |
| --- | --- |
| 全量回归 | `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8000 --timeout-seconds 120` |
| 单 case 回归 | `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8000 --case-id 8` |
| 结果整理表 | [agent-regression-tracker-20260606.xlsx](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-tracker-20260606.xlsx) |

> 备注：这些命令是历史兼容验证入口，不是产品主运行时真相。当前产品主路径是 app bundle 内的 `PikiRuntimeHost`。

## 最近结果

| 日期 | 测试仓库 | 结果文件 | 备注 |
| --- | --- | --- | --- |
| 2026-06-06 | 历史正式仓库副本 | [agent-regression-20260606-173631.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-20260606-173631.json) | 上传与 lint 失败 |
| 2026-06-11 | 轻量测试仓库副本 | [agent-regression-20260611-235716.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-20260611-235716.json) | 1-6 通过，7/8 仍待修 |
